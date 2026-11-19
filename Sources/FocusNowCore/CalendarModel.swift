import Foundation
import Observation

/// What the app shows of the owner's calendar: whether it may read it, the
/// calendars to choose from in Settings, and the Timer page's event list.
///
/// It never asks for access by itself; only `requestAccess()` does, which the
/// Settings button calls.
@MainActor @Observable
public final class CalendarModel {
    @ObservationIgnored private let source: CalendarSource
    @ObservationIgnored private let preferences: CalendarPreferences
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var todayEvents: [CalendarEvent] = []
    /// When the list next changes on its own (an event starts or ends, or midnight).
    @ObservationIgnored private var nextChange: Date = .distantPast

    public private(set) var access: CalendarAccess = .notAsked
    /// Calendars grouped by account; accounts and titles in alphabetical order.
    public private(set) var groups: [CalendarGroup] = []
    public private(set) var upcoming: UpcomingList = .empty

    public init(source: CalendarSource, preferences: CalendarPreferences,
                clock: @escaping () -> Date, calendar: Calendar) {
        self.source = source
        self.preferences = preferences
        self.clock = clock
        self.calendar = calendar
        source.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    public func isShown(_ calendarID: String) -> Bool {
        !preferences.hiddenCalendarIDs.contains(calendarID)
    }

    public func setShown(_ shown: Bool, calendarID: String) {
        if shown {
            preferences.hiddenCalendarIDs.remove(calendarID)
        } else {
            preferences.hiddenCalendarIDs.insert(calendarID)
        }
        updateUpcoming()
    }

    /// Re-reads access, the calendars and today's events.
    public func refresh() {
        access = source.access
        guard access.canRead else {
            groups = []
            todayEvents = []
            updateUpcoming()
            return
        }
        groups = Self.group(source.calendars())
        let now = clock()
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        todayEvents = source.events(in: DateInterval(start: start, end: end))
        updateUpcoming()
    }

    /// Refreshes once a listed event has started or ended, or the day changed.
    public func refreshIfDue() {
        if clock() >= nextChange { refresh() }
    }

    public func requestAccess() async {
        _ = await source.requestAccess()
        refresh()
    }

    private func updateUpcoming() {
        let now = clock()
        let hidden = preferences.hiddenCalendarIDs
        upcoming = UpcomingEvents.list(todayEvents, hidden: hidden, now: now, calendar: calendar)
        nextChange = UpcomingEvents.nextChange(todayEvents, hidden: hidden, now: now, calendar: calendar)
    }

    private static func group(_ calendars: [CalendarInfo]) -> [CalendarGroup] {
        func before(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        return Dictionary(grouping: calendars, by: \.account)
            .map { CalendarGroup(account: $0.key, calendars: $0.value.sorted { before($0.title, $1.title) }) }
            .sorted { before($0.account, $1.account) }
    }
}
