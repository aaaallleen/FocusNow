import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct TimerEngineTests {
    let h = makeEngine()
    var e: TimerEngine { h.engine }

    @Test func idleShowsTheConfiguredFocusLength() {
        #expect(e.status == .idle)
        #expect(e.nextKind == .focus)
        #expect(e.remainingSeconds == 2400)
        #expect(e.progress == 0)
    }

    @Test func countdownFollowsTheClock() {
        e.start()
        h.run(600)
        #expect(e.status == .running)
        #expect(e.remainingSeconds == 1800)
        #expect(e.progress == 0.25)
    }

    @Test func completingLogsThePlannedLength() throws {
        e.start()
        h.run(2400)
        #expect(h.sessions.records.count == 1)
        let r = try #require(h.sessions.records.first)
        #expect(r.kind == .focus)
        #expect(r.outcome == .completed)
        #expect(r.plannedSeconds == 2400)
        #expect(r.activeSeconds == 2400)
        #expect(r.startedAt == date("2026-11-19T09:00:00Z"))
        #expect(r.endedAt == date("2026-11-19T09:40:00Z"))
        #expect(r.origin == .manual)
        #expect(e.status == .idle)
        #expect(e.active == nil)
        #expect(e.needsAttention)
    }

    @Test func completionUsesTheExactEndNotTheTickTime() throws {
        e.start()
        h.run(2399)
        h.clock.advance(1.7) // a tick that arrives 0.7 s after the end
        e.tick()
        #expect((try #require(h.sessions.records.first)).endedAt == date("2026-11-19T09:40:00Z"))
        #expect((try #require(h.sessions.records.first)).activeSeconds == 2400)
    }

    @Test func onFinishIsCalledOnceWithTheKind() {
        e.start()
        h.run(2400)
        h.run(10)
        #expect(h.finished == [.focus])
    }

    @Test func pausedTimeIsNotCounted() throws {
        e.start()
        h.run(300)
        e.pause()
        h.clock.advance(900)
        e.tick()
        e.resume()
        h.run(300)
        e.endEarly()
        #expect(h.sessions.records.count == 1)
        #expect((try #require(h.sessions.records.first)).activeSeconds == 600)
        #expect((try #require(h.sessions.records.first)).outcome == .endedEarly)
        #expect((try #require(h.sessions.records.first)).endedAt == date("2026-11-19T09:25:00Z"))
    }

    @Test func pauseFreezesRemaining() {
        e.start()
        h.run(300)
        e.pause()
        h.clock.advance(900)
        e.tick()
        #expect(e.status == .paused)
        #expect(e.remainingSeconds == 2100)
    }

    @Test func endEarlyUnderOneMinuteIsDiscarded() {
        e.start()
        h.run(59)
        e.endEarly()
        #expect(h.sessions.records.isEmpty)
        #expect(e.status == .idle)
        #expect(e.nextKind == .focus)
        #expect(!e.needsAttention)
    }

    @Test func endEarlyAtExactlyOneMinuteIsLogged() throws {
        e.start()
        h.run(60)
        e.endEarly()
        #expect(h.sessions.records.count == 1)
        #expect((try #require(h.sessions.records.first)).activeSeconds == 60)
        #expect(!e.needsAttention)
        #expect(h.finished.isEmpty)
    }

    @Test func cancelLogsNothing() {
        e.start()
        h.run(900)
        e.cancel()
        #expect(h.sessions.records.isEmpty)
        #expect(e.status == .idle)
        #expect(e.nextKind == .focus)
    }

    @Test func oneOffLengthAppliesOnceOnly() {
        e.nextFocusSecondsOverride = 600
        #expect(e.remainingSeconds == 600)
        e.start()
        #expect(e.active?.plannedSeconds == 600)
        #expect(e.nextFocusSecondsOverride == nil)
        e.cancel()
        #expect(e.remainingSeconds == 2400)
    }

    @Test func changingSettingsMidSessionKeepsTheRunningLength() {
        e.start()
        h.run(60)
        h.settings.value.focusMinutes = 10
        h.run(60)
        #expect(e.active?.plannedSeconds == 2400)
        #expect(e.remainingSeconds == 2280)
    }

    @Test func invalidActionsAreIgnored() {
        e.resume()
        e.pause()
        e.endEarly()
        e.cancel()
        #expect(e.status == .idle)
        #expect(h.sessions.records.isEmpty)

        e.start()
        let id = e.active?.id
        e.start()
        #expect(e.active?.id == id)
        e.resume()
        #expect(e.status == .running)

        h.run(120)
        e.endEarly()
        e.endEarly()
        #expect(h.sessions.records.count == 1)
    }

    @Test func todayTotalIncludesTheRunningSession() {
        h.storeFocus("2026-11-19T07:00:00Z", 1500)
        h.storeFocus("2026-11-18T07:00:00Z", 2400) // yesterday: excluded
        e.start()
        h.run(300)
        #expect(e.todayFocusSeconds() == 1800)
    }

    @Test func todayTotalUpdatesAfterASessionIsSaved() {
        #expect(e.todayFocusSeconds() == 0)
        e.start()
        h.run(2400)
        #expect(e.todayFocusSeconds() == 2400)
    }
}
