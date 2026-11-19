import Foundation

/// Turns what someone types into a length field into a value. Every parser
/// clamps a number to its range and returns nil for text it can't read, so the
/// field can put its previous value back.
public enum LengthInput {
    /// "25", "25m", "25 min", "25 minutes", "1 minute": whole minutes only.
    public static func minutes(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard let match = normalized(text).wholeMatch(of: #/(\d+)\s*(?:m|mins?|minutes?)?/#) else { return nil }
        return whole(match.1).clamped(to: range)
    }

    /// "4", "4 sessions", "1 session".
    public static func sessions(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard let match = normalized(text).wholeMatch(of: #/(\d+)\s*(?:sessions?)?/#) else { return nil }
        return whole(match.1).clamped(to: range)
    }

    /// "4h", "4" (hours), "3h 30m", "3:30", "90m", "1.5h": seconds, rounded to
    /// the minute and clamped to `TimerSettings.goalRange`.
    public static func goalSeconds(_ text: String) -> Int? {
        guard let minutes = goalMinutes(normalized(text)) else { return nil }
        // Capped before converting, so an absurdly long number clamps instead of trapping.
        let seconds = Int(min(minutes.rounded(), Double(TimerSettings.goalRange.upperBound))) * 60
        return seconds.clamped(to: TimerSettings.goalRange)
    }

    // MARK: - Private

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A run of digits as an Int; one too long for Int reads as Int.max (and then clamps).
    private static func whole(_ digits: Substring) -> Int {
        Int(digits) ?? .max
    }

    /// Minutes as a Double, so no arithmetic here can overflow.
    private static func goalMinutes(_ text: String) -> Double? {
        if let m = text.wholeMatch(of: #/(\d+):(\d{2})/#) {
            guard let h = Double(m.1), let min = Double(m.2), min < 60 else { return nil }
            return h * 60 + min
        }
        if let m = text.wholeMatch(of: #/(\d+)\s*h\s*(\d+)\s*(?:m|mins?|minutes?)/#) {
            guard let h = Double(m.1), let min = Double(m.2) else { return nil }
            return h * 60 + min
        }
        if let m = text.wholeMatch(of: #/(\d+)\s*(?:m|mins?|minutes?)/#) {
            return Double(m.1)
        }
        if let m = text.wholeMatch(of: #/(\d+(?:\.\d+)?)\s*(?:h|hrs?|hours?)?/#) {
            return Double(m.1).map { $0 * 60 }
        }
        return nil
    }
}
