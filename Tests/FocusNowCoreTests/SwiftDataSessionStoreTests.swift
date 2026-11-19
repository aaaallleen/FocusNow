import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct SwiftDataSessionStoreTests {
    func record(_ iso: String, _ seconds: Int = 1500, kind: SessionKind = .focus,
                outcome: Outcome = .completed) -> SessionRecord {
        let start = date(iso)
        return SessionRecord(
            kind: kind, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(seconds)),
            plannedSeconds: 2400, activeSeconds: seconds, outcome: outcome, origin: .manual)
    }

    let all = DateInterval(start: date("2000-01-01T00:00:00Z"), end: date("2100-01-01T00:00:00Z"))

    @Test func savedRecordRoundTripsExactly() throws {
        let store = try SwiftDataSessionStore(url: nil)
        let r = record("2026-11-19T09:00:00Z", 1234, kind: .shortBreak, outcome: .endedEarly)
        store.save(r)
        #expect(store.sessions(in: all) == [r])
    }

    @Test func queryIsHalfOpenAndSortedAscending() throws {
        let store = try SwiftDataSessionStore(url: nil)
        store.save(record("2026-11-19T11:00:00Z"))
        store.save(record("2026-11-19T09:00:00Z"))
        store.save(record("2026-11-19T10:00:00Z"))
        store.save(record("2026-11-19T08:59:59Z"))
        let result = store.sessions(in: DateInterval(
            start: date("2026-11-19T09:00:00Z"), end: date("2026-11-19T11:00:00Z")))
        #expect(result.map(\.startedAt) == [date("2026-11-19T09:00:00Z"), date("2026-11-19T10:00:00Z")])
    }

    @Test func earliestStartIsNilWhenEmptyThenTheMinimum() throws {
        let store = try SwiftDataSessionStore(url: nil)
        #expect(store.earliestStart() == nil)
        store.save(record("2026-11-19T11:00:00Z"))
        store.save(record("2026-03-02T07:00:00Z"))
        #expect(store.earliestStart() == date("2026-03-02T07:00:00Z"))
    }

    @Test func dataPersistsAcrossInstancesOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focusnow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("sessions.store")
        let r = record("2026-11-19T09:00:00Z")
        do {
            let store = try SwiftDataSessionStore(url: url)
            store.save(r)
        }
        let again = try SwiftDataSessionStore(url: url)
        #expect(again.sessions(in: all) == [r])
    }

    @Test func worksAsTheEnginesStore() throws {
        let store = try SwiftDataSessionStore(url: nil)
        let clock = FakeClock(date("2026-11-19T09:00:00Z"))
        let engine = TimerEngine(
            settings: { TimerSettings() }, sessions: store, snapshots: InMemorySnapshotStore(),
            clock: { clock.now }, calendar: utc)
        engine.start()
        for _ in 0..<2400 { clock.advance(1); engine.tick() }
        #expect(store.sessions(in: all).count == 1)
        #expect(engine.todayFocusSeconds() == 2400)
    }
}
