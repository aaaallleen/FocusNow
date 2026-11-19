import Foundation
import Testing
@testable import FocusNowCore

func focus(_ iso: String, _ seconds: Int) -> SessionRecord {
    let start = date(iso)
    return SessionRecord(
        kind: .focus, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(seconds)),
        plannedSeconds: 2400, activeSeconds: seconds, outcome: .completed)
}

func rest(_ iso: String, _ seconds: Int) -> SessionRecord {
    let start = date(iso)
    return SessionRecord(
        kind: .shortBreak, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(seconds)),
        plannedSeconds: 300, activeSeconds: seconds, outcome: .completed)
}

struct StatsCalculatorTests {
    let calc = StatsCalculator(calendar: utc)
    let thursday = date("2026-11-19T12:00:00Z")

    /// Mon 7200, Tue 14400, Wed 16000, Thu 5400 (plus a break on Thu).
    let week: [SessionRecord] = [
        focus("2026-11-16T09:00:00Z", 7200),
        focus("2026-11-17T09:00:00Z", 7200), focus("2026-11-17T14:00:00Z", 7200),
        focus("2026-11-18T09:00:00Z", 16000),
        focus("2026-11-19T09:00:00Z", 2400), focus("2026-11-19T10:00:00Z", 3000),
        rest("2026-11-19T09:40:00Z", 300),
    ]

    func weekBuckets(goal: @escaping (Date) -> Int = { _ in 14_400 }) -> [StatsBucket] {
        let interval = calc.interval(for: .week, containing: thursday, earliest: nil)
        return calc.buckets(for: .week, interval: interval, sessions: week, goal: goal)
    }

    @Test func breaksAreExcludedFromTotals() {
        let sessions = [focus("2026-11-19T09:00:00Z", 1500), rest("2026-11-19T09:30:00Z", 300)]
        #expect(calc.focusSeconds(sessions) == 1500)
        #expect(calc.focusCount(sessions) == 1)
    }

    @Test func weekIntervalStartsOnTheCalendarsFirstWeekday() {
        let i = calc.interval(for: .week, containing: thursday, earliest: nil)
        #expect(i.start == date("2026-11-16T00:00:00Z"))
        #expect(i.end == date("2026-11-23T00:00:00Z"))
    }

    @Test func dayMonthAndYearIntervals() {
        #expect(calc.interval(for: .day, containing: thursday, earliest: nil)
            == DateInterval(start: date("2026-11-19T00:00:00Z"), end: date("2026-11-20T00:00:00Z")))
        #expect(calc.interval(for: .month, containing: thursday, earliest: nil)
            == DateInterval(start: date("2026-11-01T00:00:00Z"), end: date("2026-12-01T00:00:00Z")))
        #expect(calc.interval(for: .year, containing: thursday, earliest: nil)
            == DateInterval(start: date("2026-01-01T00:00:00Z"), end: date("2027-01-01T00:00:00Z")))
    }

    @Test func weekHasSevenDayBucketsWithGoals() {
        let buckets = weekBuckets()
        #expect(buckets.count == 7)
        #expect(buckets.map(\.focusSeconds) == [7200, 14_400, 16_000, 5400, 0, 0, 0])
        #expect(buckets.allSatisfy { $0.goalSeconds == 14_400 })
        #expect(buckets[0].interval.start == date("2026-11-16T00:00:00Z"))
    }

    @Test func dayHasTwentyFourHourBucketsWithoutGoals() {
        let interval = calc.interval(for: .day, containing: thursday, earliest: nil)
        let buckets = calc.buckets(
            for: .day, interval: interval, sessions: [focus("2026-11-19T09:40:00Z", 2400)], goal: { _ in 14_400 })
        #expect(buckets.count == 24)
        #expect(buckets[9].focusSeconds == 2400)
        #expect(buckets[10].focusSeconds == 0)
        #expect(buckets.allSatisfy { $0.goalSeconds == nil })
    }

    @Test func monthHasOneBucketPerDay() {
        let interval = calc.interval(for: .month, containing: thursday, earliest: nil)
        let buckets = calc.buckets(for: .month, interval: interval, sessions: week, goal: { _ in 14_400 })
        #expect(buckets.count == 30)
        #expect(buckets[18].focusSeconds == 5400) // Nov 19
        #expect(buckets[18].goalSeconds == 14_400)
    }

    @Test func yearHasTwelveMonthBuckets() {
        let interval = calc.interval(for: .year, containing: thursday, earliest: nil)
        let buckets = calc.buckets(for: .year, interval: interval, sessions: week, goal: { _ in 14_400 })
        #expect(buckets.count == 12)
        #expect(buckets[10].focusSeconds == 43_000)
        #expect(buckets[10].goalSeconds == nil)
    }

    @Test func allTimeIsMonthlyUntilTwoYearsThenYearly() {
        let short = calc.interval(for: .allTime, containing: date("2027-03-01T00:00:00Z"),
                                  earliest: date("2026-11-19T10:00:00Z"))
        #expect(short == DateInterval(start: date("2026-11-01T00:00:00Z"), end: date("2027-04-01T00:00:00Z")))
        #expect(calc.buckets(for: .allTime, interval: short, sessions: [], goal: { _ in 0 }).count == 5)

        let long = calc.interval(for: .allTime, containing: thursday, earliest: date("2024-01-10T10:00:00Z"))
        #expect(long == DateInterval(start: date("2024-01-01T00:00:00Z"), end: date("2027-01-01T00:00:00Z")))
        let yearly = calc.buckets(for: .allTime, interval: long, sessions: week, goal: { _ in 0 })
        #expect(yearly.count == 3)
        #expect(yearly[2].focusSeconds == 43_000)
    }

    @Test func allTimeWithNoSessionsIsTheCurrentMonth() {
        let i = calc.interval(for: .allTime, containing: thursday, earliest: nil)
        #expect(i == DateInterval(start: date("2026-11-01T00:00:00Z"), end: date("2026-12-01T00:00:00Z")))
    }

    @Test func aSessionCrossingMidnightBelongsToItsStartDay() {
        let interval = calc.interval(for: .week, containing: thursday, earliest: nil)
        let buckets = calc.buckets(
            for: .week, interval: interval, sessions: [focus("2026-11-19T23:50:00Z", 2400)], goal: { _ in 0 })
        #expect(buckets[3].focusSeconds == 2400)
        #expect(buckets[4].focusSeconds == 0)
    }

    @Test func summaryIgnoresFutureDays() {
        let interval = calc.interval(for: .week, containing: thursday, earliest: nil)
        let s = calc.summary(interval: interval, sessions: week, today: thursday, goal: { _ in 14_400 })
        #expect(s == StatsSummary(dailyAverageSeconds: 10_750, goalMetDays: 2, elapsedDays: 4))
    }

    @Test func summaryUsesEachDaysOwnGoal() {
        let interval = calc.interval(for: .week, containing: thursday, earliest: nil)
        let wednesday = date("2026-11-18T00:00:00Z")
        let s = calc.summary(interval: interval, sessions: week, today: thursday,
                             goal: { $0 >= wednesday ? 18_000 : 14_400 })
        #expect(s.goalMetDays == 1)
    }

    @Test func summaryOfAPastWeekCountsAllSevenDays() {
        let interval = calc.interval(for: .week, containing: thursday, earliest: nil)
        let s = calc.summary(interval: interval, sessions: week, today: date("2026-12-01T12:00:00Z"),
                             goal: { _ in 14_400 })
        #expect(s.elapsedDays == 7)
        #expect(s.dailyAverageSeconds == 43_000 / 7)
    }

    @Test func daylightSavingWeekStillHasSevenBuckets() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        la.firstWeekday = 2
        let calc = StatsCalculator(calendar: la)

        // Nov 1 2026: clocks go back (25-hour day). 23:30 PST = 07:30Z next day.
        let fall = calc.interval(for: .week, containing: date("2026-11-01T20:00:00Z"), earliest: nil)
        let fallBuckets = calc.buckets(
            for: .week, interval: fall, sessions: [focus("2026-11-02T07:30:00Z", 1500)], goal: { _ in 0 })
        #expect(fallBuckets.count == 7)
        #expect(fallBuckets[6].focusSeconds == 1500)

        // Mar 8 2026: clocks go forward (23-hour day). 23:30 PDT = 06:30Z next day.
        let spring = calc.interval(for: .week, containing: date("2026-03-08T20:00:00Z"), earliest: nil)
        let springBuckets = calc.buckets(
            for: .week, interval: spring, sessions: [focus("2026-03-09T06:30:00Z", 1500)], goal: { _ in 0 })
        #expect(springBuckets.count == 7)
        #expect(springBuckets[6].focusSeconds == 1500)

        // The 25-hour day has 25 hourly buckets.
        let day = calc.interval(for: .day, containing: date("2026-11-01T20:00:00Z"), earliest: nil)
        #expect(calc.buckets(for: .day, interval: day, sessions: [], goal: { _ in 0 }).count == 25)
    }
}
