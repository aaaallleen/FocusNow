import Foundation

/// A button the popover shows. Which ones appear depends only on the engine's state.
public enum TimerControl: Equatable, Sendable {
    case adjustLength, startFocus, startBreak, skipBreak
    case pause, resume, endEarly, cancel, skip
}

extension TimerEngine {
    public static let adjustStepMinutes = 5
    public static let adjustRangeMinutes = TimerSettings.minuteRange

    public var sessionsBeforeLongBreak: Int { currentSettings.sessionsBeforeLongBreak }

    /// True while a session is running or paused.
    public var isInSession: Bool { status != .idle }

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

    /// Changes only the next focus session's length, in steps within 1–180 minutes.
    public func adjustNextFocus(byMinutes delta: Int) {
        guard status == .idle, nextKind == .focus else { return }
        setNextFocus(minutes: plannedSecondsForNext / 60 + delta)
    }

    /// Sets only the next focus session's length, in whole minutes clamped to
    /// 1–180. Does nothing unless idle with a focus session next.
    public func setNextFocus(minutes: Int) {
        guard status == .idle, nextKind == .focus else { return }
        nextFocusSecondsOverride = minutes.clamped(to: Self.adjustRangeMinutes) * 60
    }

    /// The owner changed the Focus default: a one-off set against the old default
    /// no longer applies, even if the default is changed back before the next tick.
    public func focusDefaultChanged() {
        nextFocusSecondsOverride = nil
    }
}
