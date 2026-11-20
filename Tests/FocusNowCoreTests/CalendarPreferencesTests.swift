import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct CalendarPreferencesTests {
    let defaults = freshDefaults()

    @Test func startsWithTheDefaults() {
        let prefs = CalendarPreferences(defaults: defaults)
        #expect(prefs.showOnTimerPage == true)
        #expect(prefs.hiddenCalendarIDs == [])
        #expect(prefs.statsDisplay == .chart)
    }

    @Test func survivesANewInstanceOnTheSameDefaults() {
        let prefs = CalendarPreferences(defaults: defaults)
        prefs.showOnTimerPage = false
        prefs.hiddenCalendarIDs = ["work"]
        prefs.statsDisplay = .calendar
        let again = CalendarPreferences(defaults: defaults)
        #expect(again.showOnTimerPage == false)
        #expect(again.hiddenCalendarIDs == ["work"])
        #expect(again.statsDisplay == .calendar)
    }

    @Test func existingTimerSettingsStillLoad() {
        let clock = FakeClock(date("2026-11-19T09:00:00Z"))
        let settings = SettingsStore(defaults: defaults, clock: { clock.now }, calendar: utc)
        settings.settings.focusMinutes = 50
        let history = settings.goalHistory
        let prefs = CalendarPreferences(defaults: defaults)
        prefs.showOnTimerPage = false
        prefs.hiddenCalendarIDs = ["work", "home"]
        prefs.statsDisplay = .calendar
        let reloaded = SettingsStore(defaults: defaults, clock: { clock.now }, calendar: utc)
        #expect(reloaded.settings.focusMinutes == 50)
        #expect(reloaded.goalHistory == history)
    }

    @Test func aCorruptValueFallsBackAlone() {
        defaults.set(42, forKey: CalendarPreferences.hiddenCalendarsKey)
        defaults.set("bogus", forKey: CalendarPreferences.statsDisplayKey)
        defaults.set(false, forKey: CalendarPreferences.showOnTimerPageKey)
        let prefs = CalendarPreferences(defaults: defaults)
        #expect(prefs.hiddenCalendarIDs == [])
        #expect(prefs.statsDisplay == .chart)
        #expect(prefs.showOnTimerPage == false)
    }

    @Test func calendarIsOfferedForDayWeekMonthOnly() {
        #expect(StatsRange.allCases.filter { StatsDisplay.offersCalendar(for: $0) } == [.day, .week, .month])
        #expect(StatsDisplay.calendar.showsCalendar(for: .week))
        #expect(!StatsDisplay.calendar.showsCalendar(for: .year))
        #expect(!StatsDisplay.chart.showsCalendar(for: .day))
    }
}
