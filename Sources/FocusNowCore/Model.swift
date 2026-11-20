import Foundation

public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }
}

public enum Outcome: String, Codable, Sendable {
    case completed, endedEarly
}

public enum Origin: String, Codable, Sendable {
    case manual, schedule
}

/// One finished session, as stored.
public struct SessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: SessionKind
    public var startedAt: Date
    public var endedAt: Date
    public var plannedSeconds: Int
    public var activeSeconds: Int
    public var outcome: Outcome
    public var origin: Origin

    public init(
        id: UUID = UUID(), kind: SessionKind, startedAt: Date, endedAt: Date,
        plannedSeconds: Int, activeSeconds: Int, outcome: Outcome, origin: Origin = .manual
    ) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSeconds = plannedSeconds
        self.activeSeconds = activeSeconds
        self.outcome = outcome
        self.origin = origin
    }
}

/// The session currently running or paused.
public struct ActiveSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: SessionKind
    public var startedAt: Date
    public var plannedSeconds: Int
    /// Active time before the last resume.
    public var accumulatedSeconds: TimeInterval
    /// When the session last started or resumed; nil while paused.
    public var lastResumedAt: Date?

    public init(
        id: UUID = UUID(), kind: SessionKind, startedAt: Date, plannedSeconds: Int,
        accumulatedSeconds: TimeInterval = 0, lastResumedAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.accumulatedSeconds = accumulatedSeconds
        self.lastResumedAt = lastResumedAt
    }

    /// Active (non-blank) seconds as of `date`.
    public func activeSeconds(at date: Date) -> TimeInterval {
        guard let resumed = lastResumedAt else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, date.timeIntervalSince(resumed))
    }

    /// The moment the countdown reaches zero if it keeps running; nil while paused.
    public var endsAt: Date? {
        lastResumedAt?.addingTimeInterval(TimeInterval(plannedSeconds) - accumulatedSeconds)
    }
}

/// A focus length set on the timer, and the Focus default it was set against:
/// it stops applying once that default changes.
public struct FocusOverride: Codable, Equatable, Sendable {
    public var seconds: Int
    public var focusMinutes: Int

    public init(seconds: Int, focusMinutes: Int) {
        self.seconds = seconds
        self.focusMinutes = focusMinutes
    }
}

/// What the engine writes to disk so a crash or relaunch can recover.
public struct EngineSnapshot: Codable, Equatable, Sendable {
    public var active: ActiveSession?
    public var savedAt: Date
    public var cyclePosition: Int
    public var cycleDay: Date
    public var nextKind: SessionKind
    /// The focus length set on the timer, if any. Snapshots saved before it
    /// existed decode as nil.
    public var focusOverride: FocusOverride?

    public init(active: ActiveSession?, savedAt: Date, cyclePosition: Int, cycleDay: Date, nextKind: SessionKind,
                focusOverride: FocusOverride? = nil) {
        self.active = active
        self.savedAt = savedAt
        self.cyclePosition = cyclePosition
        self.cycleDay = cycleDay
        self.nextKind = nextKind
        self.focusOverride = focusOverride
    }
}
