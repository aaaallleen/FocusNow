import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct SettingsStoreTests {
    let defaults = freshDefaults()
    let clock = FakeClock(date("2026-11-19T09:00:00Z"))

    func makeStore() -> SettingsStore {
        let clock = self.clock
        return SettingsStore(defaults: defaults, clock: { clock.now }, calendar: utc)
    }

    @Test func defaultsMatchSpec() {
        let store = makeStore()
        #expect(store.settings == TimerSettings())
        #expect(TimerSettings().focusMinutes == 40)
        #expect(TimerSettings().shortBreakMinutes == 5)
        #expect(TimerSettings().longBreakMinutes == 15)
        #expect(TimerSettings().sessionsBeforeLongBreak == 4)
        #expect(TimerSettings().dailyGoalSeconds == 14_400)
        #expect(TimerSettings().soundOn)
    }

    @Test func settingsSurviveANewStoreOnTheSameDefaults() {
        let store = makeStore()
        store.settings.focusMinutes = 50
        #expect(makeStore().settings.focusMinutes == 50)
    }

    @Test func valuesAreClamped() {
        let store = makeStore()
        store.settings.focusMinutes = 0
        #expect(store.settings.focusMinutes == 1)
        store.settings.longBreakMinutes = 999
        #expect(store.settings.longBreakMinutes == 180)
        store.settings.sessionsBeforeLongBreak = 0
        #expect(store.settings.sessionsBeforeLongBreak == 1)
        store.settings.sessionsBeforeLongBreak = 99
        #expect(store.settings.sessionsBeforeLongBreak == 12)
        store.settings.dailyGoalSeconds = 0
        #expect(store.settings.dailyGoalSeconds == 900)
        store.settings.dailyGoalSeconds = 99_999
        #expect(store.settings.dailyGoalSeconds == 57_600)
    }

    @Test func goalHistoryIsSeededOnFirstLaunch() {
        let store = makeStore()
        #expect(store.goalHistory == [GoalChange(day: .distantPast, seconds: 14_400)])
    }

    @Test func changingTheGoalOnTheFirstDayKeepsEarlierDaysAtTheOldGoal() {
        let store = makeStore()
        store.settings.dailyGoalSeconds = 10_800
        #expect(store.goal(on: date("2026-11-19T08:00:00Z")) == 10_800)
        #expect(store.goal(on: date("2026-11-01T00:00:00Z")) == 14_400)
        #expect(store.goalHistory.count == 2)
    }

    @Test func changingGoalDoesNotRewritePastDays() {
        let store = makeStore()
        clock.advance(2 * 86_400) // 2026-11-21
        store.settings.dailyGoalSeconds = 18_000
        #expect(store.goal(on: date("2026-11-20T12:00:00Z")) == 14_400)
        #expect(store.goal(on: date("2026-11-21T08:00:00Z")) == 18_000)
        #expect(store.goal(on: date("2026-11-01T00:00:00Z")) == 14_400)
    }

    @Test func twoGoalChangesOnOneDayKeepOnlyTheLast() {
        let store = makeStore()
        clock.advance(2 * 86_400)
        store.settings.dailyGoalSeconds = 18_000
        store.settings.dailyGoalSeconds = 10_800
        #expect(store.goalHistory.count == 2)
        #expect(store.goal(on: date("2026-11-21T08:00:00Z")) == 10_800)
    }

    @Test func goalHistorySurvivesANewStore() {
        let store = makeStore()
        clock.advance(2 * 86_400)
        store.settings.dailyGoalSeconds = 18_000
        let again = makeStore()
        #expect(again.goal(on: date("2026-11-20T12:00:00Z")) == 14_400)
        #expect(again.goal(on: date("2026-11-21T08:00:00Z")) == 18_000)
    }
}
