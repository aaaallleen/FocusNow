import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct StatsViewModelTests {
    let clock = FakeClock(date("2026-11-19T12:00:00Z"))
    let store = InMemorySessionStore()
    let model: StatsViewModel

    init() {
        for r in [
            focus("2026-11-10T09:00:00Z", 1800),
            focus("2026-11-16T09:00:00Z", 7200),
            focus("2026-11-17T09:00:00Z", 3600), focus("2026-11-17T14:00:00Z", 3600),
            focus("2026-11-18T09:00:00Z", 5000),
            focus("2026-11-19T09:00:00Z", 2400), focus("2026-11-19T10:00:00Z", 1500),
            rest("2026-11-19T09:40:00Z", 300),
        ] { store.save(r) }
        let clock = self.clock
        model = StatsViewModel(sessions: store, goal: { _ in 14_400 }, clock: { clock.now }, calendar: utc)
    }

    @Test func tilesCoverAllFiveRanges() {
        #expect(model.tiles[.day] == .init(focusSeconds: 3900, sessionCount: 2))
        #expect(model.tiles[.week] == .init(focusSeconds: 23_300, sessionCount: 6))
        #expect(model.tiles[.month] == .init(focusSeconds: 25_100, sessionCount: 7))
        #expect(model.tiles[.year] == .init(focusSeconds: 25_100, sessionCount: 7))
        #expect(model.tiles[.allTime] == .init(focusSeconds: 25_100, sessionCount: 7))
    }

    @Test func defaultsToTheCurrentWeek() {
        #expect(model.range == .week)
        #expect(model.interval.start == date("2026-11-16T00:00:00Z"))
        #expect(model.buckets.map(\.focusSeconds) == [7200, 7200, 5000, 3900, 0, 0, 0])
        #expect(model.summary == StatsSummary(dailyAverageSeconds: 5825, goalMetDays: 0, elapsedDays: 4))
        #expect(model.todayGoalSeconds == 14_400)
    }

    @Test func defaultListIsToday() {
        #expect(model.listInterval == DateInterval(start: date("2026-11-19T00:00:00Z"), end: date("2026-11-20T00:00:00Z")))
        #expect(model.listedSessions.map(\.startedAt) == [date("2026-11-19T09:00:00Z"), date("2026-11-19T10:00:00Z")])
    }

    @Test func selectingABarListsThatBar() {
        model.selectedBucketID = date("2026-11-17T00:00:00Z")
        #expect(model.listInterval.start == date("2026-11-17T00:00:00Z"))
        #expect(model.listedSessions.map(\.activeSeconds) == [3600, 3600])
        model.selectedBucketID = nil
        #expect(model.listInterval.start == date("2026-11-19T00:00:00Z"))
    }

    @Test func selectingAnHourBarListsThatHour() {
        model.range = .day
        #expect(model.buckets.count == 24)
        model.selectedBucketID = date("2026-11-19T10:00:00Z")
        #expect(model.listedSessions.map(\.activeSeconds) == [1500])
    }

    @Test func pagingBackShowsTheLatestDayWithSessions() {
        model.pageBack()
        #expect(model.interval.start == date("2026-11-09T00:00:00Z"))
        #expect(model.listedSessions.map(\.startedAt) == [date("2026-11-10T09:00:00Z")])
        #expect(model.listInterval.start == date("2026-11-10T00:00:00Z"))
        #expect(model.canPageForward)
        #expect(model.summary.elapsedDays == 7)
    }

    @Test func pagingBackToAnEmptyPeriodListsNothing() {
        model.pageBack(); model.pageBack()
        #expect(model.listedSessions.isEmpty)
    }

    @Test func pagingForwardStopsAtNow() {
        #expect(!model.canPageForward)
        model.pageForward()
        #expect(model.interval.start == date("2026-11-16T00:00:00Z"))
        model.pageBack(); model.pageForward()
        #expect(model.interval.start == date("2026-11-16T00:00:00Z"))
        #expect(!model.canPageForward)
    }

    @Test func changingRangeClearsSelectionAndReturnsToNow() {
        model.pageBack()
        model.selectedBucketID = date("2026-11-10T00:00:00Z")
        model.range = .month
        #expect(model.selectedBucketID == nil)
        #expect(model.interval == DateInterval(start: date("2026-11-01T00:00:00Z"), end: date("2026-12-01T00:00:00Z")))
        #expect(model.buckets.count == 30)
    }

    @Test func allTimeCannotPage() {
        model.range = .allTime
        #expect(!model.canPageBack)
        #expect(!model.canPageForward)
        let before = model.interval
        model.pageBack()
        #expect(model.interval == before)
        #expect(model.buckets.count == 1)
    }

    @Test func tilesDoNotChangeWhenPaging() {
        let before = model.tiles
        model.pageBack()
        model.range = .year
        model.pageBack()
        #expect(model.tiles == before)
    }

    @Test func reloadPicksUpANewSession() {
        store.save(focus("2026-11-19T11:00:00Z", 600))
        model.reload()
        #expect(model.tiles[.day] == .init(focusSeconds: 4500, sessionCount: 3))
        #expect(model.listedSessions.count == 3)
    }

    @Test func reloadFollowsTheClockIntoANewDay() {
        clock.advance(86_400) // Friday
        model.reload()
        #expect(model.tiles[.day] == .init(focusSeconds: 0, sessionCount: 0))
        #expect(model.listInterval.start == date("2026-11-20T00:00:00Z"))
    }
}
