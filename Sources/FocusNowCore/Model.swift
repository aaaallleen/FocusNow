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
