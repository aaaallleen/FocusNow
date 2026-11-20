import Foundation

/// One line of the Timer page's event list.
public struct UpcomingRow: Equatable, Sendable {
    public var event: CalendarEvent
    /// Under way now: the row reads "Now … until <end>".
    public var isNow: Bool

    public init(event: CalendarEvent, isNow: Bool) {
        self.event = event
        self.isNow = isNow
    }
}

/// The rows shown and how many more there are ("+N more").
public struct UpcomingList: Equatable, Sendable {
    public var rows: [UpcomingRow]
    public var moreCount: Int

    public init(rows: [UpcomingRow], moreCount: Int) {
        self.rows = rows
        self.moreCount = moreCount
    }

    public static let empty = UpcomingList(rows: [], moreCount: 0)

    /// The first `count` rows; the rest add to "+N more".
    public func trimmed(to count: Int) -> UpcomingList {
        guard rows.count > count else { return self }
        let kept = Array(rows.prefix(max(0, count)))
        return UpcomingList(rows: kept, moreCount: moreCount + rows.count - kept.count)
    }
}

/// Which of today's events the Timer page lists, and when that changes next.
public enum UpcomingEvents {
    public static let limit = 3

    /// Today's timed events that haven't ended, from shown calendars, leaving
    /// out declined and cancelled ones; in start order, then by title.
    public static func list(_ events: [CalendarEvent], hidden: Set<String>, now: Date,
                            calendar: Calendar, limit: Int = limit) -> UpcomingList {
        let kept = remaining(events, hidden: hidden, now: now, calendar: calendar)
        let rows = kept.prefix(limit).map { UpcomingRow(event: $0, isNow: $0.start <= now) }
        return UpcomingList(rows: Array(rows), moreCount: kept.count - rows.count)
    }

    /// The next moment the list changes on its own: a listed event starting or
    /// ending, or midnight at the latest.
    public static func nextChange(_ events: [CalendarEvent], hidden: Set<String>, now: Date,
                                  calendar: Calendar) -> Date {
        let midnight = startOfTomorrow(after: now, calendar: calendar)
        let moments = remaining(events, hidden: hidden, now: now, calendar: calendar)
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > now }
        return min(moments.min() ?? midnight, midnight)
    }

    private static func remaining(_ events: [CalendarEvent], hidden: Set<String>, now: Date,
                                  calendar: Calendar) -> [CalendarEvent] {
        let midnight = startOfTomorrow(after: now, calendar: calendar)
        return events
            .filter { e in
                e.end > now && e.start < midnight && !e.isAllDay && !e.isDeclined && !e.isCancelled
                    && !hidden.contains(e.calendarID)
            }
            .sorted { a, b in
                a.start != b.start ? a.start < b.start
                    : a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    private static func startOfTomorrow(after now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    }
}
