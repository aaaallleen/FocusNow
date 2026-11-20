import Foundation

/// A button the popover shows. Which ones appear depends only on the engine's state.
public enum TimerControl: Equatable, Sendable {
    case adjustLength, startFocus, startBreak, skipBreak
    case pause, resume, endEarly, cancel, skip
}

/// The buttons in two rows: the main action alone on top, the rest beneath.
public struct ControlRows: Equatable, Sendable {
    public var main: TimerControl
    public var others: [TimerControl]

    public init(main: TimerControl, others: [TimerControl]) {
        self.main = main
        self.others = others
    }
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

    /// `controls` split into rows: start, pause or resume on top, the rest beneath.
    public var controlRows: ControlRows {
        let all = controls
        let mainControls: [TimerControl] = [.startFocus, .startBreak, .pause, .resume]
        guard let main = all.first(where: mainControls.contains) else {
            return ControlRows(main: all[0], others: Array(all.dropFirst()))
        }
        return ControlRows(main: main, others: all.filter { $0 != main })
    }

    /// Changes the set focus length in steps, within 1–180 minutes.
    public func adjustNextFocus(byMinutes delta: Int) {
        guard status == .idle, nextKind == .focus else { return }
        setNextFocus(minutes: plannedSecondsForNext / 60 + delta)
    }

    /// Sets the focus length, in whole minutes clamped to 1–180, until it's set
    /// again or the Focus default changes. Does nothing unless idle with a
    /// focus session next. Saved, so it survives a relaunch.
    public func setNextFocus(minutes: Int) {
        guard status == .idle, nextKind == .focus else { return }
        nextFocusSecondsOverride = minutes.clamped(to: Self.adjustRangeMinutes) * 60
        saveSnapshot()
    }

    /// The owner changed the Focus default: a length set against the old default
    /// no longer applies, even if the default is changed back before the next tick.
    public func focusDefaultChanged() {
        nextFocusSecondsOverride = nil
        saveSnapshot()
    }
}
