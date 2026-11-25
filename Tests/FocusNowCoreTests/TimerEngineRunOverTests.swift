import Foundation
import Testing
@testable import FocusNowCore

/// Allow time to run over: a focus that reaches zero keeps counting up until
/// Start break, Skip break, or 10 idle minutes. Focus is 2400 s from 09:00Z.
@MainActor
struct TimerEngineRunOverTests {
    let h: Harness
    var e: TimerEngine { h.engine }

    init() {
        h = makeEngine()
        h.settings.value.allowRunOver = true
    }

    @Test func reachingZeroKeepsTheFocusRunning() {
        e.start(); h.run(2400)
        #expect(e.status == .running); #expect(e.isRunningOver); #expect(e.needsAttention)
        #expect(h.finished == [.focus]); #expect(h.sessions.records.isEmpty)
        #expect(e.remainingSeconds == 0); #expect(e.progress == 1)
        h.run(252)
        #expect(e.overtimeSeconds == 252); #expect(h.finished == [.focus])
    }

    @Test func startBreakEndsTheFocusWithItsFullTime() throws {
        e.start(); h.run(2700); e.start()
        #expect(h.sessions.records.count == 1)
        let r = try #require(h.sessions.records.first)
        #expect(r.kind == .focus); #expect(r.outcome == .completed)
        #expect(r.plannedSeconds == 2400); #expect(r.activeSeconds == 2700)
        #expect(r.endedAt == date("2026-11-19T09:45:00Z"))
        #expect(e.status == .running); #expect(e.active?.kind == .shortBreak)
        #expect(!e.needsAttention); #expect(e.cyclePosition == 1); #expect(h.finished == [.focus])
    }

    @Test func skipBreakEndsTheFocusAndSkipsTheBreak() {
        e.start(); h.run(2460); e.skipBreak()
        #expect(h.sessions.records.map(\.activeSeconds) == [2460])
        #expect(e.status == .idle); #expect(e.nextKind == .focus); #expect(e.cyclePosition == 1)
        #expect(!e.needsAttention); #expect(e.phaseLabel == "FOCUS · 2 of 4")
    }

    @Test func pausedTimeIsNotCounted() {
        e.start(); h.run(2460); e.pause(); h.run(120)
        #expect(e.overtimeSeconds == 60)
        e.resume(); h.run(30); e.start()
        #expect(h.sessions.records.first?.activeSeconds == 2490)
    }

    @Test func tenIdleMinutesEndTheFocusAtTheLastInput() throws {
        e.start(); h.run(3300)                       // 15 min over
        h.idleSeconds = 599; e.tick()
        #expect(e.isRunningOver)
        h.idleSeconds = 600; e.tick()                // last input 5 min after zero
        let r = try #require(h.sessions.records.first)
        #expect(r.activeSeconds == 2700); #expect(r.outcome == .completed)
        #expect(r.endedAt == date("2026-11-19T09:45:00Z"))
        #expect(e.status == .idle); #expect(e.nextKind == .shortBreak)
        #expect(e.needsAttention); #expect(h.finished == [.focus])
    }

    @Test func idleStopNeverEndsBeforeZero() {
        e.start(); h.run(2460); h.idleSeconds = 900; e.tick()
        #expect(h.sessions.records.first?.activeSeconds == 2400)
        #expect(h.sessions.records.first?.endedAt == date("2026-11-19T09:40:00Z"))
    }

    @Test func idleIsIgnoredBeforeZeroAndWhilePaused() {
        h.idleSeconds = 900
        e.start(); h.run(600)
        #expect(e.status == .running)
        h.idleSeconds = 0; h.run(1860); e.pause(); h.idleSeconds = 900; h.run(5)
        #expect(e.status == .paused); #expect(h.sessions.records.isEmpty)
    }

    @Test func switchOffFinishesAtZeroAsBefore() {
        h.settings.value.allowRunOver = false
        e.start(); h.run(2400)
        #expect(e.status == .idle); #expect(!e.isRunningOver)
        #expect(h.sessions.records.first?.activeSeconds == 2400)
    }

    @Test func switchingOffWhileRunningOverKeepsCounting() {
        e.start(); h.run(2410); h.settings.value.allowRunOver = false; h.run(10)
        #expect(e.isRunningOver); #expect(e.overtimeSeconds == 20)
    }

    @Test func switchingOnMidFocusAppliesAtZero() {
        h.settings.value.allowRunOver = false
        e.start(); h.run(100); h.settings.value.allowRunOver = true; h.run(2300)
        #expect(e.isRunningOver)
    }

    @Test func breaksNeverRunOver() {
        e.start(); h.run(2400); e.start(); h.run(300)
        #expect(e.status == .idle); #expect(e.nextKind == .focus)
        #expect(h.sessions.records.last?.kind == .shortBreak)
        #expect(h.sessions.records.last?.activeSeconds == 300)
    }

    @Test func blankGapKeepsTheExtraTime() {
        e.start(); h.run(2460); h.clock.advance(120); e.tick()
        #expect(e.status == .paused); #expect(e.overtimeSeconds == 60)
    }

    @Test func relaunchLogsTheFocusAsCompletedWithItsExtraTime() throws {
        e.start(); h.run(2500)
        let engine = h.relaunch()
        #expect(h.sessions.records.count == 1)
        let r = try #require(h.sessions.records.first)
        #expect(r.outcome == .completed); #expect((2485...2500).contains(r.activeSeconds))
        #expect(engine.status == .idle); #expect(engine.nextKind == .shortBreak); #expect(!engine.needsAttention)
    }

    @Test func snapshotSavedBeforeRunOverStillDecodes() throws {
        let start = date("2026-11-19T09:00:00Z")
        let snap = EngineSnapshot(
            active: ActiveSession(kind: .focus, startedAt: start, plannedSeconds: 2400, lastResumedAt: start),
            savedAt: date("2026-11-19T09:10:00Z"), cyclePosition: 0, cycleDay: date("2026-11-19T00:00:00Z"),
            nextKind: .focus)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as? [String: Any])
        var active = try #require(json["active"] as? [String: Any])
        active.removeValue(forKey: "timeUpAt"); json["active"] = active
        let decoded = try JSONDecoder().decode(EngineSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.active?.timeUpAt == nil); #expect(decoded.active?.plannedSeconds == 2400)
    }

    /// Quitting (⌘Q, logging out, restarting) while running over: the focus
    /// did reach zero, so it's a finished one, with all its time.
    @Test func quittingWhileRunningOverLogsACompletedFocus() throws {
        e.start(); h.run(2700); e.prepareForQuit()
        #expect(h.sessions.records.count == 1)
        let r = try #require(h.sessions.records.first)
        #expect(r.outcome == .completed); #expect(r.activeSeconds == 2700)
    }

    @Test func quittingWhilePausedRunningOverLogsACompletedFocus() throws {
        e.start(); h.run(2700); e.pause(); h.run(60); e.prepareForQuit()
        #expect(h.sessions.records.count == 1)
        let r = try #require(h.sessions.records.first)
        #expect(r.outcome == .completed); #expect(r.activeSeconds == 2700)
    }

    /// The Mac sleeping from idleness before the 10-minute stop: the idle
    /// minutes before the sleep don't count either.
    @Test func sleepAfterIdleMinutesDoesNotCountThem() {
        e.start(); h.run(2760)                 // input stops 60 s after zero
        h.idleSeconds = 300; e.systemWillSleep()
        #expect(e.status == .paused); #expect(e.overtimeSeconds == 60)
        e.start()
        #expect(h.sessions.records.first?.activeSeconds == 2460)
    }

    @Test func blankGapAfterIdleMinutesDoesNotCountThem() {
        e.start(); h.run(2660)                 // input stops 60 s after zero
        h.clock.advance(120); h.idleSeconds = 320; e.tick()
        #expect(e.status == .paused); #expect(e.overtimeSeconds == 60)
    }

    @Test func idleIsNeverTrimmedBeforeZero() {
        e.start(); h.run(2430)
        h.idleSeconds = 900; e.systemWillSleep()
        #expect(e.overtimeSeconds == 0); #expect(e.isRunningOver)
    }

    @Test func todayTotalIncludesTheExtraTime() {
        e.start(); h.run(2500)
        #expect(e.todayFocusSeconds() == 2500)
    }
}
