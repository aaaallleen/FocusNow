import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct TimerEngineBlankTests {
    let h = makeEngine()
    var e: TimerEngine { h.engine }

    // MARK: Blank time

    @Test func sleepIsBlankTime() throws {
        e.start(); h.run(180)
        e.systemWillSleep()
        h.clock.advance(7200)
        e.tick()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 2220)
        e.resume(); h.run(2220)
        #expect(try #require(h.sessions.records.first).activeSeconds == 2400)
    }

    @Test func aTickGapWithoutASleepNoticeIsBlankTime() {
        e.start(); h.run(180)
        h.clock.advance(7200)
        e.tick()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 2220)
        #expect(h.sessions.records.isEmpty)
        #expect(h.finished.isEmpty)
    }

    @Test func aGapOfThirtySecondsOrLessStillCounts() {
        e.start(); h.run(180)
        h.clock.advance(30)
        e.tick()
        #expect(e.status == .running)
        #expect(e.remainingSeconds == 2190)
    }

    @Test func aGapAcrossTheEndPausesInsteadOfCompleting() {
        e.start(); h.run(2390)
        h.clock.advance(600)
        e.tick()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 10)
        #expect(h.sessions.records.isEmpty)
    }

    @Test func aGapBeforeALateSleepNoticeIsBlank() throws {
        e.start(); h.run(180)
        h.clock.advance(7200)
        e.systemWillSleep()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 2220)
        e.resume(); h.run(2220)
        #expect(try #require(h.sessions.records.first).activeSeconds == 2400)
        #expect(h.sessions.records.first?.endedAt == date("2026-11-19T11:40:00Z"))
    }

    @Test func aGapBeforeEndEarlyIsBlank() {
        e.start(); h.run(180)
        h.clock.advance(1200)
        e.endEarly()
        #expect(h.sessions.records.first?.activeSeconds == 180)
    }

    @Test func aGapBeforeQuitIsBlank() {
        e.start(); h.run(180)
        h.clock.advance(1200)
        e.prepareForQuit()
        #expect(h.sessions.records.first?.activeSeconds == 180)
    }

    @Test func aGapBeforePauseIsBlank() {
        e.start(); h.run(180)
        h.clock.advance(1200)
        e.pause()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 2220)
    }

    @Test func aGapBeforeSkippingABreakIsBlank() {
        e.start(); h.run(2400)
        e.start(); h.run(60)
        h.clock.advance(1200)
        e.skipBreak()
        #expect(h.sessions.records.last?.kind == .shortBreak)
        #expect(h.sessions.records.last?.activeSeconds == 60)
    }

    @Test func sleepWhilePausedOrIdleChangesNothing() {
        e.systemWillSleep()
        #expect(e.status == .idle)
        e.start(); h.run(60); e.pause()
        e.systemWillSleep()
        h.clock.advance(3600); e.tick()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 2340)
    }

    // MARK: Snapshots

    @Test func snapshotIsSavedOnStateChangeAndEveryFifteenSeconds() throws {
        e.start()
        #expect(h.snapshots.snapshot?.active != nil)
        let first = try #require(h.snapshots.snapshot).savedAt
        h.run(14)
        #expect(h.snapshots.snapshot?.savedAt == first)
        h.run(1)
        #expect(h.snapshots.snapshot?.savedAt == first.addingTimeInterval(15))
    }

    @Test func pauseIsSnapshotted() {
        e.start(); h.run(20); e.pause()
        #expect(h.snapshots.snapshot?.active?.lastResumedAt == nil)
        #expect(h.snapshots.snapshot?.active?.accumulatedSeconds == 20)
    }

    // MARK: Quit

    @Test func quitLogsARunningFocusAsEndedEarly() throws {
        e.start(); h.run(600)
        e.prepareForQuit()
        let r = try #require(h.sessions.records.first)
        #expect(h.sessions.records.count == 1)
        #expect(r.activeSeconds == 600)
        #expect(r.outcome == .endedEarly)
        #expect(h.snapshots.snapshot != nil)
        #expect(h.snapshots.snapshot?.active == nil)
    }

    @Test func quitLogsAPausedFocus() {
        e.start(); h.run(300); e.pause(); h.clock.advance(100)
        e.prepareForQuit()
        #expect(h.sessions.records.first?.activeSeconds == 300)
    }

    @Test func quitUnderOneMinuteLogsNothing() {
        e.start(); h.run(59)
        e.prepareForQuit()
        #expect(h.sessions.records.isEmpty)
        #expect(h.snapshots.snapshot != nil)
        #expect(h.snapshots.snapshot?.active == nil)
    }

    @Test func quitWhileIdleLogsNothing() {
        e.prepareForQuit()
        #expect(h.sessions.records.isEmpty)
    }

    // MARK: Recovery

    @Test func crashRecoveryLogsUpToTheLastSnapshot() throws {
        e.start(); h.run(620) // last periodic snapshot at 615 s
        h.clock.advance(3600)
        let e2 = h.relaunch()
        let r = try #require(h.sessions.records.first)
        #expect(r.activeSeconds == 615)
        #expect(r.outcome == .endedEarly)
        #expect(r.endedAt == date("2026-11-19T09:10:15Z"))
        #expect(e2.status == .idle)
        #expect(!e2.needsAttention)
        #expect(e2.cyclePosition == 1)
        #expect(e2.nextKind == .shortBreak)
        #expect(h.finished.isEmpty)
    }

    @Test func recoveryHappensOnlyOnce() {
        e.start(); h.run(620)
        h.relaunch()
        h.relaunch()
        #expect(h.sessions.records.count == 1)
    }

    @Test func recoveryOfAShortFocusLogsNothing() {
        e.start(); h.run(40)
        let e2 = h.relaunch()
        #expect(h.sessions.records.isEmpty)
        #expect(e2.cyclePosition == 0)
        #expect(e2.nextKind == .focus)
    }

    @Test func relaunchRestoresThePendingBreakAndCyclePosition() {
        e.start(); h.run(2400)
        h.clock.advance(60)
        let e2 = h.relaunch()
        #expect(e2.nextKind == .shortBreak)
        #expect(e2.cyclePosition == 1)
        #expect(h.sessions.records.count == 1)
    }

    @Test func relaunchOnANewDayStartsAFreshCycle() {
        e.start(); h.run(2400)
        h.clock.advance(86_400)
        let e2 = h.relaunch()
        #expect(e2.nextKind == .focus)
        #expect(e2.cyclePosition == 0)
    }

    // MARK: File store

    @Test func fileStoreRoundTripsASnapshot() throws {
        let url = tempURL()
        let snapshot = EngineSnapshot(
            active: ActiveSession(kind: .focus, startedAt: date("2026-11-19T09:00:00Z"), plannedSeconds: 2400,
                                  accumulatedSeconds: 12.5, lastResumedAt: date("2026-11-19T09:01:00Z")),
            savedAt: date("2026-11-19T09:02:00Z"), cyclePosition: 2,
            cycleDay: date("2026-11-19T00:00:00Z"), nextKind: .focus)
        FileSnapshotStore(url: url).save(snapshot)
        #expect(FileSnapshotStore(url: url).load() == snapshot)
    }

    @Test func missingSnapshotFileLoadsNil() {
        #expect(FileSnapshotStore(url: tempURL()).load() == nil)
    }

    @Test func corruptSnapshotFileStartsIdle() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let clock = h.clock
        let engine = TimerEngine(
            settings: { TimerSettings() }, sessions: h.sessions, snapshots: FileSnapshotStore(url: url),
            clock: { clock.now }, calendar: utc)
        #expect(engine.status == .idle)
        #expect(engine.nextKind == .focus)
        #expect(h.sessions.records.isEmpty)
    }

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("focusnow-tests-\(UUID().uuidString)")
            .appendingPathComponent("engine-snapshot.json")
    }
}
