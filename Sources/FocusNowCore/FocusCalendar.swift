import Foundation

/// One focus session as the Stats calendar draws it: from its start, as long
/// as the time actually focused (a paused session ends early on the calendar,
/// and one left paused overnight can't stretch the view), cut at midnight.
public struct FocusBlock: Equatable, Sendable {
    public var sessionID: UUID
    public var start: Date
    public var end: Date
    /// Wall-clock hours of the day, e.g. 10.5 for 10:30; an end at midnight is 24.
    public var startHour: Double
    public var endHour: Double

    public init(sessionID: UUID, start: Date, end: Date, startHour: Double, endHour: Double) {
        self.sessionID = sessionID
        self.start = start
        self.end = end
        self.startHour = startHour
        self.endHour = endHour
    }
}

/// Blocks with only a break between them, read as one stretch: "10–12 am".
public struct FocusPeriod: Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// One day of the Stats calendar.
public struct FocusDay: Equatable, Identifiable, Sendable {
    public var day: DateInterval
    /// Focus time of the sessions started this day, as the stats count it.
    public var focusSeconds: Int
    public var blocks: [FocusBlock]
    public var periods: [FocusPeriod]
    public var id: Date { day.start }

    public init(day: DateInterval, focusSeconds: Int, blocks: [FocusBlock], periods: [FocusPeriod]) {
        self.day = day
        self.focusSeconds = focusSeconds
        self.blocks = blocks
        self.periods = periods
    }
}

/// The hours of the day a Today or This week calendar shows: `first..<last`.
public struct HourSpan: Equatable, Sendable {
    public var first: Int
    public var last: Int

    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }
}

/// Lays out focus sessions for the Stats calendar. Times are wall-clock
/// times of `calendar`, so clock-change days place blocks where the clock read.
public struct FocusCalendar: Sendable {
    /// Blocks less than this apart join into one period.
    public static let joinGap: TimeInterval = 900
    public static let minimumHours = 6

    private let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// Focus sessions only, in start order.
    public func blocks(_ sessions: [SessionRecord]) -> [FocusBlock] {
        sessions
            .filter { $0.kind == .focus }
            .sorted { $0.startedAt < $1.startedAt }
            .map { session in
                let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: session.startedAt))!
                let end = min(session.startedAt.addingTimeInterval(TimeInterval(session.activeSeconds)), midnight)
                return FocusBlock(
                    sessionID: session.id, start: session.startedAt, end: end,
                    startHour: hour(of: session.startedAt), endHour: end >= midnight ? 24 : hour(of: end))
            }
    }

    /// Joins blocks on the same day that are less than `joinGap` apart.
    public func periods(_ blocks: [FocusBlock]) -> [FocusPeriod] {
        var result: [FocusPeriod] = []
        for block in blocks.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, block.start.timeIntervalSince(last.end) < Self.joinGap,
               calendar.isDate(block.start, inSameDayAs: last.start) {
                result[result.count - 1].end = max(last.end, block.end)
            } else {
                result.append(FocusPeriod(start: block.start, end: block.end))
            }
        }
        return result
    }

    /// One entry per calendar day in `interval`, each with the sessions started that day.
    public func days(in interval: DateInterval, sessions: [SessionRecord]) -> [FocusDay] {
        var result: [FocusDay] = []
        var cursor = interval.start
        while cursor < interval.end, let day = calendar.dateInterval(of: .day, for: cursor) {
            let started = sessions.filter { $0.kind == .focus && $0.startedAt >= day.start && $0.startedAt < day.end }
            let dayBlocks = blocks(started)
            result.append(FocusDay(
                day: day, focusSeconds: started.reduce(0) { $0 + $1.activeSeconds },
                blocks: dayBlocks, periods: periods(dayBlocks)))
            cursor = day.end
        }
        return result
    }

    /// An hour of padding before the earliest block and after the latest, and
    /// at least `minimumHours` so one short session isn't a full-height block.
    public func hourSpan(_ blocks: [FocusBlock]) -> HourSpan? {
        guard let earliest = blocks.map(\.startHour).min(), let latest = blocks.map(\.endHour).max() else { return nil }
        var first = max(0, Int(earliest.rounded(.down)) - 1)
        var last = min(24, Int(latest.rounded(.up)) + 1)
        if last - first < Self.minimumHours { last = min(24, first + Self.minimumHours) }
        if last - first < Self.minimumHours { first = max(0, last - Self.minimumHours) }
        return HourSpan(first: first, last: last)
    }

    /// The month's days in rows of seven, starting on the calendar's first
    /// weekday; days outside the month are nil. As many rows as the month spans (4–6).
    public func monthWeeks(_ month: DateInterval) -> [[Date?]] {
        var cells: [Date?] = []
        let weekday = calendar.component(.weekday, from: month.start)
        cells += Array(repeating: nil, count: (weekday - calendar.firstWeekday + 7) % 7)
        var cursor = month.start
        while cursor < month.end {
            cells.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func hour(of date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
}

/// A period as the month view writes it: "10–11:50 am", "11:30 am–1 pm",
/// or with 24-hour time "10:00–11:50". A period cut at midnight ends "12 am"
/// (24-hour: "24:00").
public enum PeriodFormat {
    public static func text(_ period: FocusPeriod, calendar: Calendar, uses24Hour: Bool) -> String {
        let s = calendar.dateComponents([.hour, .minute], from: period.start)
        let e = calendar.dateComponents([.hour, .minute], from: period.end)
        let (sh, sm, eh, em) = (s.hour ?? 0, s.minute ?? 0, e.hour ?? 0, e.minute ?? 0)
        let sameDay = calendar.isDate(period.start, inSameDayAs: period.end)

        if uses24Hour {
            func clock(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }
            return clock(sh, sm) + "–" + (sameDay ? clock(eh, em) : clock(24, 0))
        }

        func time(_ h: Int, _ m: Int) -> String {
            let h12 = h % 12 == 0 ? 12 : h % 12
            return m == 0 ? "\(h12)" : String(format: "%d:%02d", h12, m)
        }
        func half(_ h: Int) -> String { h < 12 ? "am" : "pm" }
        if sameDay && half(sh) == half(eh) {
            return "\(time(sh, sm))–\(time(eh, em)) \(half(eh))"
        }
        return "\(time(sh, sm)) \(half(sh))–\(time(eh, em)) \(half(eh))"
    }
}
