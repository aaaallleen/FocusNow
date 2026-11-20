import Foundation
@testable import FocusNowCore

/// A clock tests move by hand.
final class FakeClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Gregorian, UTC, weeks start on Monday.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

/// "2026-11-19T09:00:00Z" → Date
func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    guard let d = f.date(from: iso) else { fatalError("bad date \(iso)") }
    return d
}

func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "focusnow-tests-\(UUID().uuidString)")!
}

/// Settings a test can change while an engine is running.
@MainActor final class SettingsBox {
    var value = TimerSettings()
}

/// One engine plus the fakes it runs on. `relaunch()` builds a second engine on
/// the same stores and clock, as if the app had been started again.
@MainActor final class Harness {
    let clock: FakeClock
    let sessions = InMemorySessionStore()
    let snapshots = InMemorySnapshotStore()
    let settings = SettingsBox()
    private(set) var engine: TimerEngine!
    private(set) var finished: [SessionKind] = []

    init(at iso: String) {
        clock = FakeClock(date(iso))
        engine = newEngine()
    }

    func newEngine() -> TimerEngine {
        let settings = self.settings
        let clock = self.clock
        let engine = TimerEngine(
            settings: { settings.value }, sessions: sessions, snapshots: snapshots,
            clock: { clock.now }, calendar: utc)
        engine.onFinish = { [weak self] kind in self?.finished.append(kind) }
        return engine
    }

    /// Advances the clock in 1-second steps, ticking after each.
    func run(_ seconds: Int) {
        for _ in 0..<seconds {
            clock.advance(1)
            engine.tick()
        }
    }

    @discardableResult
    func relaunch() -> TimerEngine {
        engine = newEngine()
        return engine
    }

    func storeFocus(_ iso: String, _ seconds: Int) {
        let start = date(iso)
        sessions.save(SessionRecord(
            kind: .focus, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(seconds)),
            plannedSeconds: seconds, activeSeconds: seconds, outcome: .completed))
    }
}

@MainActor func makeEngine(at iso: String = "2026-11-19T09:00:00Z") -> Harness {
    Harness(at: iso)
}

/// A timed calendar event; times are ISO 8601 ("2026-11-19T10:00:00Z").
func event(_ id: String, _ start: String, _ end: String, calendar: String = "work", title: String? = nil,
           allDay: Bool = false, declined: Bool = false, cancelled: Bool = false) -> CalendarEvent {
    CalendarEvent(
        id: id, calendarID: calendar, title: title ?? id, start: date(start), end: date(end),
        isAllDay: allDay, isDeclined: declined, isCancelled: cancelled,
        color: CalendarColor(red: 0.2, green: 0.4, blue: 0.6))
}
