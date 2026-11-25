import AppKit
import EventKit
import FocusNowCore

/// The owner's calendars, through EventKit: every account added to the
/// Calendar app on this Mac. One store for the app's lifetime.
///
/// Nothing here asks for access except `requestAccess()`, which only the
/// Settings button calls.
@MainActor
final class EventKitCalendarSource: CalendarSource {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var accessChange = AccessChange()
    var onChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    /// Every look at access also catches it becoming readable, from the
    /// Allow Access prompt or from System Settings while the app runs, and
    /// resets the store so it reads the calendars it couldn't before.
    var access: CalendarAccess {
        let access: CalendarAccess = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .notDetermined: .notAsked
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
        if accessChange.becameReadable(access) { store.reset() }
        return access
    }

    func requestAccess() async -> CalendarAccess {
        guard access == .notAsked else { return access }
        let store = self.store
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // @Sendable, so the handler isn't main-actor-isolated: EventKit calls
            // it off the main queue, and an isolated handler would trap there.
            store.requestFullAccessToEvents { @Sendable granted, _ in continuation.resume(returning: granted) }
        }
        return access // resets the store if access was granted
    }

    func calendars() -> [CalendarInfo] {
        guard access.canRead else { return [] }
        return store.calendars(for: .event).map { calendar in
            CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                         account: calendar.source?.title ?? "Other", color: Self.color(calendar.cgColor))
        }
    }

    func events(in interval: DateInterval) -> [CalendarEvent] {
        guard access.canRead else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate else { return nil }
            let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
            // Occurrences of a repeating event share one identifier; the start tells them apart.
            let id = "\(event.eventIdentifier ?? UUID().uuidString)@\(start.timeIntervalSinceReferenceDate)"
            return CalendarEvent(
                id: id, calendarID: calendar.calendarIdentifier, title: event.title ?? "",
                start: start, end: end, isAllDay: event.isAllDay, isDeclined: declined,
                isCancelled: event.status == .canceled, color: Self.color(calendar.cgColor))
        }
    }

    private static func color(_ cgColor: CGColor?) -> CalendarColor {
        guard let cgColor, let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return CalendarColor(red: 0.5, green: 0.5, blue: 0.5)
        }
        return CalendarColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }
}
