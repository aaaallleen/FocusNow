import Foundation

public enum StatsRange: String, CaseIterable, Sendable {
    case day, week, month, year, allTime
}

public struct StatsBucket: Equatable, Identifiable, Sendable {
    public var interval: DateInterval
    public var focusSeconds: Int
    /// The goal for this bucket's day; set only for day-sized buckets.
    public var goalSeconds: Int?
    public var id: Date { interval.start }

    public init(interval: DateInterval, focusSeconds: Int, goalSeconds: Int?) {
        self.interval = interval
        self.focusSeconds = focusSeconds
        self.goalSeconds = goalSeconds
    }
}

public struct StatsSummary: Equatable, Sendable {
    public var dailyAverageSeconds: Int
    public var goalMetDays: Int
    public var elapsedDays: Int

    public init(dailyAverageSeconds: Int, goalMetDays: Int, elapsedDays: Int) {
        self.dailyAverageSeconds = dailyAverageSeconds
        self.goalMetDays = goalMetDays
        self.elapsedDays = elapsedDays
    }
}

/// Pure stats arithmetic. Only focus sessions count; a session belongs wholly
/// to the bucket containing its start. Calendar units are stepped with the
/// calendar, never by adding fixed seconds, so daylight-saving days work.
public struct StatsCalculator: Sendable {
    /// All time switches from monthly to yearly bars past this many months.
    public static let maxMonthlyBuckets = 24

    private let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func focusSeconds(_ sessions: [SessionRecord]) -> Int {
        sessions.lazy.filter { $0.kind == .focus }.reduce(0) { $0 + $1.activeSeconds }
    }

    public func focusCount(_ sessions: [SessionRecord]) -> Int {
        sessions.lazy.filter { $0.kind == .focus }.count
    }

    public func interval(for range: StatsRange, containing date: Date, earliest: Date?) -> DateInterval {
        switch range {
        case .day: return unit(.day, containing: date)
        case .week: return unit(.weekOfYear, containing: date)
        case .month: return unit(.month, containing: date)
        case .year: return unit(.year, containing: date)
        case .allTime:
            let first = min(earliest ?? date, date)
            let monthly = DateInterval(start: unit(.month, containing: first).start,
                                       end: unit(.month, containing: date).end)
            guard monthCount(monthly) > Self.maxMonthlyBuckets else { return monthly }
            return DateInterval(start: unit(.year, containing: first).start, end: unit(.year, containing: date).end)
        }
    }

    public func buckets(
        for range: StatsRange, interval: DateInterval, sessions: [SessionRecord], goal: (Date) -> Int
    ) -> [StatsBucket] {
        let component = bucketComponent(for: range, interval: interval)
        let subs = subintervals(of: interval, by: component)
        return zip(subs, focusSecondsPer(subs, sessions: sessions)).map { sub, seconds in
            StatsBucket(interval: sub, focusSeconds: seconds,
                        goalSeconds: component == .day ? goal(sub.start) : nil)
        }
    }

    public func summary(
        interval: DateInterval, sessions: [SessionRecord], today: Date, goal: (Date) -> Int
    ) -> StatsSummary {
        let days = subintervals(of: interval, by: .day).filter { $0.start <= today }
        guard !days.isEmpty else { return StatsSummary(dailyAverageSeconds: 0, goalMetDays: 0, elapsedDays: 0) }
        let perDay = focusSecondsPer(days, sessions: sessions)
        let total = perDay.reduce(0, +)
        let met = zip(days, perDay).filter { $1 >= goal($0.start) }.count
        return StatsSummary(dailyAverageSeconds: total / days.count, goalMetDays: met, elapsedDays: days.count)
    }

    // MARK: - Helpers

    private func unit(_ component: Calendar.Component, containing date: Date) -> DateInterval {
        calendar.dateInterval(of: component, for: date)!
    }

    private func bucketComponent(for range: StatsRange, interval: DateInterval) -> Calendar.Component {
        switch range {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        case .allTime: monthCount(interval) > Self.maxMonthlyBuckets ? .year : .month
        }
    }

    private func monthCount(_ interval: DateInterval) -> Int {
        subintervals(of: interval, by: .month).count
    }

    /// Consecutive calendar units covering `interval`.
    private func subintervals(of interval: DateInterval, by component: Calendar.Component) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            let sub = unit(component, containing: cursor)
            result.append(sub)
            cursor = sub.end
        }
        return result
    }

    /// Focus seconds of the sessions starting in each half-open interval.
    private func focusSecondsPer(_ intervals: [DateInterval], sessions: [SessionRecord]) -> [Int] {
        let focus = sessions.filter { $0.kind == .focus }
        return intervals.map { i in
            focus.filter { $0.startedAt >= i.start && $0.startedAt < i.end }.reduce(0) { $0 + $1.activeSeconds }
        }
    }
}
