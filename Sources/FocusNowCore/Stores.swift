import Foundation

@MainActor
public protocol SessionStore: AnyObject {
    func save(_ record: SessionRecord)
    /// Records whose `startedAt` is in `[interval.start, interval.end)`, oldest first.
    func sessions(in interval: DateInterval) -> [SessionRecord]
    func earliestStart() -> Date?
}

@MainActor
public protocol SnapshotStore: AnyObject {
    func load() -> EngineSnapshot?
    func save(_ snapshot: EngineSnapshot)
}

@MainActor
public final class InMemorySessionStore: SessionStore {
    public var records: [SessionRecord] = []

    public init() {}

    public func save(_ record: SessionRecord) {
        records.append(record)
    }

    public func sessions(in interval: DateInterval) -> [SessionRecord] {
        records
            .filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func earliestStart() -> Date? {
        records.map(\.startedAt).min()
    }
}

@MainActor
public final class InMemorySnapshotStore: SnapshotStore {
    public var snapshot: EngineSnapshot?

    public init() {}

    public func load() -> EngineSnapshot? { snapshot }
    public func save(_ snapshot: EngineSnapshot) { self.snapshot = snapshot }
}
