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
