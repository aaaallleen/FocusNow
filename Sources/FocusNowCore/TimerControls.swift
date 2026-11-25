import Foundation

/// A button the popover shows. Which ones appear depends only on the engine's state.
public enum TimerControl: Equatable, Sendable {
    case adjustLength, startFocus, startBreak, skipBreak
    case pause, resume, endEarly, cancel, skip
    /// Flow: start one with no set length, and stop it.
    case startFlow, stop
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
        // A flow ends when the owner stops it; it has no break of its own.
        if isFlowing { return status == .paused ? [.resume, .stop] : [.stop, .pause] }
        if flowIsNext { return [.startFlow] }
        // Past zero the focus is done: what's left is taking the break or not.
        if isRunningOver {
            return status == .paused ? [.resume, .startBreak, .skipBreak] : [.startBreak, .pause, .skipBreak]
        }
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

    /// The digits to show: the countdown, "+4:12" past zero while running
    /// over, or a flow's time so far (no "+": it has no zero to pass).
    public var clockLabel: String {
        if isFlowing { return TimeFormat.clock(overtimeSeconds) }
        if flowIsNext { return TimeFormat.clock(0) }
        return isRunningOver ? "+" + TimeFormat.clock(overtimeSeconds) : TimeFormat.clock(remainingSeconds)
    }

    /// Idle with Flow chosen and a focus next: Start begins a flow.
    var flowIsNext: Bool { status == .idle && nextKind == .focus && flowChosen }

    /// The line under the Focus | Flow switch: where the cycle stands ("1 of 4",
    /// "BREAK", "LONG BREAK"), or nothing for a flow, which is outside it.
    public var cycleLine: String {
        if isFlowing || flowIsNext { return "" }
        let label = phaseLabel
        return label.hasPrefix("FOCUS · ") ? String(label.dropFirst("FOCUS · ".count)) : label
    }

    /// A flow's ring: hours done, and how far through this one (0..<1). Nil
    /// unless a flow is running or paused.
    public var flowLap: (completed: Int, fraction: Double)? {
        guard isFlowing else { return nil }
        let seconds = overtimeSeconds
        return (seconds / 3600, Double(seconds % 3600) / 3600)
    }

    /// `controls` split into rows: start, pause or resume on top, the rest beneath.
    public var controlRows: ControlRows {
        let all = controls
        let mainControls: [TimerControl] = [.startFocus, .startFlow, .startBreak, .pause, .resume, .stop]
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
