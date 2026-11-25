import Foundation
import Testing
@testable import FocusNowCore

/// Flow: a focus with no set length that counts up from 00:00 until Stop (or
/// 10 idle minutes), saved as focus, outside the Pomodoro cycle. From 09:00Z.
@MainActor
struct TimerEngineFlowTests {
    let h = makeEngine()
    var e: TimerEngine { h.engine }

    @Test func startFlowCountsUpFromZero() {
        h.settings.value.allowRunOver = true                  // flow ignores the run-over switch
        e.chooseFlow(true); e.start(); h.run(3130)
        #expect(e.isFlowing); #expect(e.status == .running); #expect(e.overtimeSeconds == 3130)
        #expect(!e.needsAttention); #expect(h.finished.isEmpty)
    }

    @Test func stopSavesACompletedFlowAndReturnsToIdle() throws {
        e.chooseFlow(true); e.start(); h.run(3130); e.stop()
        let r = try #require(h.sessions.records.first)
        #expect(h.sessions.records.count == 1); #expect(r.isFlow); #expect(r.plannedSeconds == 0)
        #expect(r.outcome == .completed); #expect(r.activeSeconds == 3130)
        #expect(e.status == .idle); #expect(e.flowChosen); #expect(!e.needsAttention)
    }

    @Test func aFlowUnderAMinuteIsNotSaved() {
        e.chooseFlow(true); e.start(); h.run(59); e.stop()
        #expect(h.sessions.records.isEmpty); #expect(e.status == .idle)
    }

    @Test func flowLeavesTheCycleAlone() {
        e.start(); h.run(2400); e.skipBreak()                 // a Pomodoro: 1 of 4 done
        e.chooseFlow(true); e.start(); h.run(3000); e.stop()
        #expect(e.cyclePosition == 1); #expect(e.nextKind == .focus)
        e.chooseFlow(false)
        #expect(e.phaseLabel == "FOCUS · 2 of 4")
    }

    @Test func aNewDayAfterAFlowStillResetsTheCycle() {
        e.start(); h.run(2400); e.skipBreak()                 // 09:40, 1 of 4 done
        h.clock.advance(12 * 3600)                            // 21:40
        e.chooseFlow(true); e.start(); h.run(4 * 3600); e.stop() // flows past midnight, stops 01:40
        h.run(600)                                            // 01:50: a flow that set cycleDay or lastFinishAt
        #expect(e.cyclePosition == 0)                         // would block this reset (grace period)
    }

    @Test func startAndSkipBreakDoNothingWhileFlowing() {
        e.chooseFlow(true); e.start(); h.run(600); e.start(); e.skipBreak()
        #expect(e.isFlowing); #expect(h.sessions.records.isEmpty)
    }

    @Test func tenIdleMinutesStopAFlowAtTheLastInput() throws {
        e.chooseFlow(true); e.start(); h.run(1500)
        h.idleSeconds = 600; e.tick()
        let r = try #require(h.sessions.records.first)
        #expect(r.activeSeconds == 900); #expect(r.isFlow)
        #expect(e.status == .idle); #expect(!e.needsAttention); #expect(h.finished.isEmpty)
    }

    @Test func sleepPausesAFlowAtTheLastInput() {
        e.chooseFlow(true); e.start(); h.run(1500)
        h.idleSeconds = 300; e.systemWillSleep()
        #expect(e.status == .paused); #expect(e.overtimeSeconds == 1200)
    }

    @Test func quittingSavesAFlow() throws {
        e.chooseFlow(true); e.start(); h.run(1500); e.prepareForQuit()
        let r = try #require(h.sessions.records.first)
        #expect(r.isFlow); #expect(r.outcome == .completed); #expect(r.activeSeconds == 1500)
    }

    @Test func relaunchAfterACrashSavesAFlow() throws {
        e.chooseFlow(true); e.start(); h.run(1500)
        let engine = h.relaunch()
        let r = try #require(h.sessions.records.first)
        #expect(r.isFlow); #expect(r.outcome == .completed); #expect((1485...1500).contains(r.activeSeconds))
        #expect(engine.status == .idle); #expect(engine.cyclePosition == 0); #expect(!engine.needsAttention)
    }

    @Test func theSwitchIsLockedExceptWhileIdleWithAFocusNext() {
        #expect(e.canChooseFlow)
        e.start(); #expect(!e.canChooseFlow); e.chooseFlow(true); #expect(!e.flowChosen)
        h.run(2400); #expect(!e.canChooseFlow)                // a break is pending
        e.skipBreak(); #expect(e.canChooseFlow)
        e.chooseFlow(true); e.start(); #expect(!e.canChooseFlow)
    }

    @Test func theSwitchSurvivesARelaunch() {
        e.chooseFlow(true)
        #expect(h.relaunch().flowChosen)
    }

    @Test func snapshotSavedBeforeFlowStillDecodes() throws {
        let snap = EngineSnapshot(active: nil, savedAt: date("2026-11-19T09:10:00Z"), cyclePosition: 2,
                                  cycleDay: date("2026-11-19T00:00:00Z"), nextKind: .focus)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as? [String: Any])
        json.removeValue(forKey: "flowChosen")
        let decoded = try JSONDecoder().decode(EngineSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.flowChosen == nil); #expect(decoded.cyclePosition == 2)
    }
}
