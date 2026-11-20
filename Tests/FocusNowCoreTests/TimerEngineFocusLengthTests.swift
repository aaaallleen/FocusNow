import Foundation
import Testing
@testable import FocusNowCore

/// A focus length set on the timer (typed, or with − / +) stays until it's set
/// again or the Focus default changes. The default here is 40 minutes.
@MainActor
struct TimerEngineFocusLengthTests {
    let h = makeEngine()
    var e: TimerEngine { h.engine }

    @Test func staysAfterStartAndCancel() {
        e.setNextFocus(minutes: 25)
        e.start()
        #expect(e.active?.plannedSeconds == 1500)
        e.cancel()
        #expect(e.remainingSeconds == 1500)
    }

    @Test func staysThroughFinishAndBreak() {
        e.setNextFocus(minutes: 25)
        e.start(); h.run(1500)
        #expect(e.remainingSeconds == 300)
        e.start(); h.run(300)
        #expect(e.nextKind == .focus)
        #expect(e.remainingSeconds == 1500)
    }

    @Test func staysAfterEndEarly() {
        e.setNextFocus(minutes: 25)
        e.start(); h.run(120)
        e.endEarly()
        e.skipBreak()
        #expect(e.remainingSeconds == 1500)
    }

    @Test func staysOnANewDay() {
        e.setNextFocus(minutes: 25)
        h.clock.advance(86_400)
        e.tick()
        #expect(e.remainingSeconds == 1500)
    }

    @Test func survivesRelaunch() {
        e.setNextFocus(minutes: 25)
        h.relaunch()
        #expect(h.engine.remainingSeconds == 1500)
    }

    @Test func relaunchWithAChangedFocusDefaultDropsTheLength() {
        e.setNextFocus(minutes: 25)
        h.settings.value.focusMinutes = 30
        h.relaunch()
        #expect(h.engine.remainingSeconds == 1800)
        #expect(h.engine.nextFocusSecondsOverride == nil)
    }

    @Test func settingAgainReplacesIt() {
        e.setNextFocus(minutes: 25)
        e.start(); e.cancel()
        e.adjustNextFocus(byMinutes: 5)
        #expect(e.remainingSeconds == 1800)
    }

    /// What a build from before set lengths were saved wrote: no length.
    @Test func snapshotWithoutALengthDecodes() throws {
        let old = #"{"savedAt":0,"cyclePosition":1,"cycleDay":0,"nextKind":"shortBreak"}"#
        let snapshot = try JSONDecoder().decode(EngineSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.focusOverride == nil)
        #expect(snapshot.nextKind == .shortBreak)
    }
}
