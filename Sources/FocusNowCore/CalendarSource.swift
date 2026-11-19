import Foundation

/// Whether FocusNow may read the Mac's calendars.
public enum CalendarAccess: String, Sendable {
    /// Never asked; FocusNow asks only when the owner presses Allow Access.
    case notAsked
    case granted
    /// Denied, or restricted by the system.
    case denied
    /// macOS 14's "add events only": events can't be read.
    case writeOnly

    public var canRead: Bool { self == .granted }
}

/// A calendar's colour, as sRGB components 0...1.
public struct CalendarColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// One calendar on this Mac.
public struct CalendarInfo: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// The account it belongs to: "iCloud", a Google address, "On My Mac".
    public var account: String
    public var color: CalendarColor

    public init(id: String, title: String, account: String, color: CalendarColor) {
        self.id = id
        self.title = title
        self.account = account
        self.color = color
    }
}

/// One event occurrence.
public struct CalendarEvent: Equatable, Identifiable, Sendable {
    public var id: String
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The owner declined the invitation.
    public var isDeclined: Bool
    public var isCancelled: Bool
    public var color: CalendarColor

    public init(id: String, calendarID: String, title: String, start: Date, end: Date,
                isAllDay: Bool, isDeclined: Bool, isCancelled: Bool, color: CalendarColor) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isCancelled = isCancelled
        self.color = color
    }
}

/// The calendars of one account, as Settings lists them.
public struct CalendarGroup: Equatable, Sendable {
    public var account: String
    public var calendars: [CalendarInfo]

    public init(account: String, calendars: [CalendarInfo]) {
        self.account = account
        self.calendars = calendars
    }
}

/// Where calendars and events come from: EventKit in the app, a fake in
/// tests and the self-check (which must never read the owner's calendar).
@MainActor
public protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    /// Shows the system prompt if access was never asked; returns the access after.
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    /// Events overlapping `interval`, from every calendar.
    func events(in interval: DateInterval) -> [CalendarEvent]
    /// Called when calendars, events or access change.
    var onChange: (() -> Void)? { get set }
}

/// Made-up calendars and events, for tests and the self-check.
@MainActor
public final class FakeCalendarSource: CalendarSource {
    public var access: CalendarAccess
    /// What the "system prompt" answers when access is requested.
    public var grantsOnRequest: Bool
    public var calendarList: [CalendarInfo]
    public var eventList: [CalendarEvent]
    public var onChange: (() -> Void)?
    public private(set) var requestCount = 0

    public init(access: CalendarAccess = .notAsked, calendars: [CalendarInfo] = [],
                events: [CalendarEvent] = [], grantsOnRequest: Bool = true) {
        self.access = access
        self.calendarList = calendars
        self.eventList = events
        self.grantsOnRequest = grantsOnRequest
    }

    public func requestAccess() async -> CalendarAccess {
        requestCount += 1
        if access == .notAsked { access = grantsOnRequest ? .granted : .denied }
        return access
    }

    public func calendars() -> [CalendarInfo] {
        access.canRead ? calendarList : []
    }

    public func events(in interval: DateInterval) -> [CalendarEvent] {
        guard access.canRead else { return [] }
        return eventList.filter { $0.end > interval.start && $0.start < interval.end }
    }

    /// As if the calendar database changed.
    public func simulateChange() {
        onChange?()
    }
}
