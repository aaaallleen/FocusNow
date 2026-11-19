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

    @Test func adjustingIsClampedToFiveThroughOneEighty() {
        for _ in 0..<20 { e.adjustNextFocus(byMinutes: -5) }
        #expect(e.remainingSeconds == 300)
        for _ in 0..<50 { e.adjustNextFocus(byMinutes: 5) }
        #expect(e.remainingSeconds == 10_800)
    }

    @Test func adjustingOnlyAppliesBeforeFocus() {
        e.start()
        e.adjustNextFocus(byMinutes: 5)
        #expect(e.nextFocusSecondsOverride == nil)
        #expect(e.active?.plannedSeconds == 2400)
    }
}
