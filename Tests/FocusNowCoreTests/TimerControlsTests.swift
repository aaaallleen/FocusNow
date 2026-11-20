import Testing
@testable import FocusNowCore

@MainActor
struct TimerControlsTests {
    let h = makeEngine()
    var e: TimerEngine { h.engine }

    @Test func idleBeforeFocus() {
        #expect(e.controls == [.adjustLength, .startFocus])
        #expect(e.phaseLabel == "FOCUS · 1 of 4")
    }

    @Test func focusRunningAndPaused() {
        e.start()
        #expect(e.controls == [.pause, .endEarly, .cancel])
        #expect(e.phaseLabel == "FOCUS · 1 of 4")
        e.pause()
        #expect(e.controls == [.resume, .endEarly, .cancel])
    }

    @Test func idleBeforeABreak() {
        e.start(); h.run(2400)
        #expect(e.controls == [.startBreak, .skipBreak])
        #expect(e.phaseLabel == "BREAK")
    }

    @Test func breakRunningAndPaused() {
        e.start(); h.run(2400); e.start()
        #expect(e.controls == [.pause, .skip])
        #expect(e.phaseLabel == "BREAK")
        e.pause()
        #expect(e.controls == [.resume, .skip])
    }

    @Test func longBreakLabel() {
        for _ in 0..<3 { e.start(); h.run(2400); e.start(); h.run(300) }
        e.start(); h.run(2400)
        #expect(e.phaseLabel == "LONG BREAK")
    }

    @Test func secondFocusLabel() {
        e.start(); h.run(2400); e.start(); h.run(300)
        #expect(e.phaseLabel == "FOCUS · 2 of 4")
    }

    @Test func labelNeverExceedsTheCycleLength() {
        e.start(); h.run(2400); e.skipBreak()
        e.start(); h.run(2400); e.skipBreak()
        h.settings.value.sessionsBeforeLongBreak = 1
        #expect(e.phaseLabel == "FOCUS · 1 of 1")
    }

    @Test func adjustingTheNextFocusStepsByFiveMinutes() {
        e.adjustNextFocus(byMinutes: 5)
        #expect(e.remainingSeconds == 2700)
        e.adjustNextFocus(byMinutes: -5)
        e.adjustNextFocus(byMinutes: -5)
        #expect(e.remainingSeconds == 2100)
        #expect(h.settings.value.focusMinutes == 40)
    }

    @Test func adjustingIsClampedToOneThroughOneEighty() {
        e.setNextFocus(minutes: 3)
        e.adjustNextFocus(byMinutes: -5)
        #expect(e.remainingSeconds == 60)
        for _ in 0..<50 { e.adjustNextFocus(byMinutes: 5) }
        #expect(e.remainingSeconds == 10_800)
    }

    @Test func typingTheNextFocusLengthSetsOnlyTheNextSession() {
        e.setNextFocus(minutes: 25)
        #expect(e.remainingSeconds == 1500)
        #expect(h.settings.value.focusMinutes == 40)
        e.start()
        #expect(e.active?.plannedSeconds == 1500)
    }

    @Test func typedLengthIsClamped() {
        e.setNextFocus(minutes: 0)
        #expect(e.remainingSeconds == 60)
        e.setNextFocus(minutes: 999)
        #expect(e.remainingSeconds == 10_800)
    }

    @Test func typingOnlyAppliesBeforeAFocusSession() {
        e.start()
        e.setNextFocus(minutes: 25)
        #expect(e.nextFocusSecondsOverride == nil)
        h.run(2400) // short break pending
        e.setNextFocus(minutes: 25)
        #expect(e.nextFocusSecondsOverride == nil)
        #expect(e.remainingSeconds == 300)
    }

    @Test func changingTheFocusDefaultDropsTheOneOff() {
        e.adjustNextFocus(byMinutes: 5)
        h.settings.value.focusMinutes = 30
        #expect(e.remainingSeconds == 1800)
        #expect(e.nextFocusSecondsOverride == nil)
        e.tick()
        h.settings.value.focusMinutes = 40
        #expect(e.remainingSeconds == 2400)
    }

    /// Changed and changed back between two ticks: the value matches again, but
    /// the owner did change the default, so the one-off stays gone.
    @Test func aFocusDefaultChangedAndChangedBackStillDropsTheOneOff() {
        e.adjustNextFocus(byMinutes: 5)
        h.settings.value.focusMinutes = 30
        e.focusDefaultChanged()
        h.settings.value.focusMinutes = 40
        e.focusDefaultChanged()
        #expect(e.nextFocusSecondsOverride == nil)
        #expect(e.remainingSeconds == 2400)
    }

    @Test func otherSettingsChangesKeepTheOneOff() {
        e.adjustNextFocus(byMinutes: 5)
        h.settings.value.shortBreakMinutes = 7
        h.settings.value.dailyGoalSeconds = 3600
        #expect(e.remainingSeconds == 2700)
    }

    @Test func inASessionWhileRunningOrPausedOnly() {
        #expect(!e.isInSession)
        e.start(); #expect(e.isInSession)
        e.pause(); #expect(e.isInSession)
        e.resume(); h.run(2400)
        #expect(!e.isInSession) // break pending
        e.start(); #expect(e.isInSession)
        e.skipBreak(); #expect(!e.isInSession)
    }

    @Test func adjustingOnlyAppliesBeforeFocus() {
        e.start()
        e.adjustNextFocus(byMinutes: 5)
        #expect(e.nextFocusSecondsOverride == nil)
        #expect(e.active?.plannedSeconds == 2400)
    }

    @Test func controlRowsForEveryState() {
        #expect(e.controlRows == ControlRows(main: .startFocus, others: [.adjustLength]))
        e.start()
        #expect(e.controlRows == ControlRows(main: .pause, others: [.endEarly, .cancel]))
        e.pause()
        #expect(e.controlRows == ControlRows(main: .resume, others: [.endEarly, .cancel]))
        e.resume(); h.run(2400)
        #expect(e.controlRows == ControlRows(main: .startBreak, others: [.skipBreak]))
        e.start()
        #expect(e.controlRows == ControlRows(main: .pause, others: [.skip]))
        e.pause()
        #expect(e.controlRows == ControlRows(main: .resume, others: [.skip]))
    }
}
