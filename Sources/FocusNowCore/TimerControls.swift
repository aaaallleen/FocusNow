import Foundation

/// A button the popover shows. Which ones appear depends only on the engine's state.
public enum TimerControl: Equatable, Sendable {
    case adjustLength, startFocus, startBreak, skipBreak
    case pause, resume, endEarly, cancel, skip
}

extension TimerEngine {
    public static let adjustStepMinutes = 5
    public static let adjustRangeMinutes = 5...180

    public var sessionsBeforeLongBreak: Int { currentSettings.sessionsBeforeLongBreak }

    /// The current (or, when idle, next) phase: "FOCUS · 2 of 4", "BREAK", "LONG BREAK".
    public var phaseLabel: String {
        switch active?.kind ?? nextKind {
        case .focus:
            let total = sessionsBeforeLongBreak
            return "FOCUS · \(min(cyclePosition + 1, total)) of \(total)"
        case .shortBreak: return "BREAK"
        case .longBreak: return "LONG BREAK"
        }
    }

    public var controls: [TimerControl] {
        let isBreak = (active?.kind ?? nextKind).isBreak
        switch (status, isBreak) {
        case (.idle, false): return [.adjustLength, .startFocus]
        case (.idle, true): return [.startBreak, .skipBreak]
        case (.running, false): return [.pause, .endEarly, .cancel]
        case (.paused, false): return [.resume, .endEarly, .cancel]
        case (.running, true): return [.pause, .skip]
        case (.paused, true): return [.resume, .skip]
        }
    }

    /// Changes only the next focus session's length, in 5-minute steps within 5–180 minutes.
    public func adjustNextFocus(byMinutes delta: Int) {
        guard status == .idle, nextKind == .focus else { return }
        let range = Self.adjustRangeMinutes
        let minutes = (plannedSecondsForNext / 60 + delta).clamped(to: range)
        nextFocusSecondsOverride = minutes * 60
    }
}
