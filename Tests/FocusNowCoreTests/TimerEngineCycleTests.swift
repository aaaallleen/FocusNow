import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct TimerEngineCycleTests {
    let h = makeEngine()
    var e: TimerEngine { h.engine }

    /// Runs a full focus session then a full short break.
    func focusThenBreak() {
        e.start(); h.run(2400)
        e.start(); h.run(300)
    }

    @Test func focusIsFollowedByAShortBreak() {
        e.start(); h.run(2400)
        #expect(e.nextKind == .shortBreak)
        #expect(e.cyclePosition == 1)
        #expect(e.remainingSeconds == 300)
    }

    @Test func breakIsFollowedByFocus() {
        focusThenBreak()
        #expect(e.nextKind == .focus)
        #expect(e.needsAttention)
        #expect(h.sessions.records.map(\.kind) == [.focus, .shortBreak])
        #expect(h.finished == [.focus, .shortBreak])
        #expect(e.remainingSeconds == 2400)
    }

    @Test func fourthFocusIsFollowedByALongBreak() {
        for _ in 0..<3 { focusThenBreak() }
        e.start(); h.run(2400)
        #expect(e.cyclePosition == 4)
        #expect(e.nextKind == .longBreak)
        #expect(e.remainingSeconds == 900)
        e.start(); h.run(900)
        #expect(e.cyclePosition == 0)
        #expect(e.nextKind == .focus)
        #expect(h.sessions.records.last?.kind == .longBreak)
    }

    @Test func skippingAPendingBreakSavesNothing() {
        e.start(); h.run(2400)
        e.skipBreak()
        #expect(e.nextKind == .focus)
        #expect(e.status == .idle)
        #expect(h.sessions.records.count == 1)
        #expect(!e.needsAttention)
        #expect(e.cyclePosition == 1)
    }

    @Test func skippingARunningBreakLogsItsActiveTime() {
        e.start(); h.run(2400)
        e.start(); h.run(120)
        e.skipBreak()
        let last = h.sessions.records.last
        #expect(last?.kind == .shortBreak)
        #expect(last?.outcome == .endedEarly)
        #expect(last?.activeSeconds == 120)
        #expect(e.status == .idle)
        #expect(e.nextKind == .focus)
        #expect(!e.needsAttention)
    }

    @Test func skippingAPausedBreakLogsItsActiveTime() {
        e.start(); h.run(2400)
        e.start(); h.run(30); e.pause(); h.clock.advance(600); e.tick()
        e.skipBreak()
        #expect(h.sessions.records.last?.activeSeconds == 30)
        #expect(e.nextKind == .focus)
    }

    @Test func skippingALongBreakResetsTheCycle() {
        for _ in 0..<3 { focusThenBreak() }
        e.start(); h.run(2400)
        #expect(e.nextKind == .longBreak)
        e.skipBreak()
        #expect(e.cyclePosition == 0)
        #expect(e.nextKind == .focus)
    }

    @Test func skippingARunningLongBreakResetsTheCycle() {
        for _ in 0..<3 { focusThenBreak() }
        e.start(); h.run(2400)
        e.start(); h.run(100)
        e.skipBreak()
        #expect(e.cyclePosition == 0)
        #expect(e.nextKind == .focus)
        #expect(h.sessions.records.last?.kind == .longBreak)
    }

    @Test func skipBreakDuringFocusDoesNothing() {
        e.start(); h.run(60)
        e.skipBreak()
        #expect(e.status == .running)
        #expect(e.active?.kind == .focus)
        #expect(h.sessions.records.isEmpty)
    }

    @Test func skipBreakWhenFocusIsNextDoesNothing() {
        e.skipBreak()
        #expect(e.nextKind == .focus)
        #expect(e.cyclePosition == 0)
    }

    @Test func endedEarlyFocusCountsTowardTheCycle() {
        e.start(); h.run(600)
        e.endEarly()
        #expect(e.cyclePosition == 1)
        #expect(e.nextKind == .shortBreak)
        #expect(!e.needsAttention)
    }

    @Test func discardedFocusDoesNotCount() {
        e.start(); h.run(30)
        e.endEarly()
        #expect(e.cyclePosition == 0)
        #expect(e.nextKind == .focus)
    }

    @Test func cancelledFocusDoesNotCount() {
        e.start(); h.run(600)
        e.cancel()
        #expect(e.cyclePosition == 0)
        #expect(e.nextKind == .focus)
    }

    @Test func acknowledgeOnlyStopsTheFlash() {
        e.start(); h.run(2400)
        e.acknowledge()
        #expect(!e.needsAttention)
        #expect(e.nextKind == .shortBreak)
        #expect(e.status == .idle)
    }

    @Test func startClearsAttention() {
        e.start(); h.run(2400)
        #expect(e.needsAttention)
        e.start()
        #expect(!e.needsAttention)
        #expect(e.active?.kind == .shortBreak)
    }

    @Test func oneOffLengthNeverAppliesToBreaks() {
        e.start(); h.run(2400)
        e.nextFocusSecondsOverride = 600
        #expect(e.remainingSeconds == 300)
        e.start()
        #expect(e.active?.plannedSeconds == 300)
        h.run(300)
        #expect(e.nextFocusSecondsOverride == 600)
        #expect(e.remainingSeconds == 600)
    }

    @Test func breakLengthsComeFromSettings() {
        h.settings.value.shortBreakMinutes = 7
        e.start(); h.run(2400)
        #expect(e.remainingSeconds == 420)
    }

    @Test func loweringTheLongBreakIntervalAppliesAtOnce() {
        focusThenBreak()
        e.start(); h.run(1200)
        h.settings.value.sessionsBeforeLongBreak = 2
        h.run(1200)
        #expect(e.nextKind == .longBreak)
    }

    @Test func aNewDayResetsTheCycle() {
        e.start(); h.run(2400) // 09:40, short break pending, cyclePosition 1
        h.clock.advance(86_400)
        e.tick()
        e.start()
        #expect(e.active?.kind == .focus)
        #expect(e.cyclePosition == 0)
    }

    @Test func aNewDayResetsTheIdleDisplayBeforeStart() {
        e.start(); h.run(2400)
        h.clock.advance(86_400)
        e.tick()
        #expect(e.nextKind == .focus)
        #expect(e.cyclePosition == 0)
        #expect(e.remainingSeconds == 2400)
    }

    @Test func aSessionRunningAcrossMidnightIsNotInterrupted() {
        let h = makeEngine(at: "2026-11-19T23:50:00Z")
        h.engine.start(); h.run(2400)
        h.run(5) // idle ticks after midnight must not wipe the pending break
        #expect(h.sessions.records.count == 1)
        #expect(h.engine.nextKind == .shortBreak)
        #expect(h.engine.cyclePosition == 1)
    }
}
