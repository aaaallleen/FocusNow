import Foundation
import SwiftData

@Model
final class StoredSession {
    @Attribute(.unique) var id: UUID
    var kind: String
    var startedAt: Date
    var endedAt: Date
    var plannedSeconds: Int
    var activeSeconds: Int
    var outcome: String
    var origin: String

    init(_ r: SessionRecord) {
        id = r.id
        kind = r.kind.rawValue
        startedAt = r.startedAt
        endedAt = r.endedAt
        plannedSeconds = r.plannedSeconds
        activeSeconds = r.activeSeconds
        outcome = r.outcome.rawValue
        origin = r.origin.rawValue
    }

    var record: SessionRecord? {
        guard let kind = SessionKind(rawValue: kind), let outcome = Outcome(rawValue: outcome) else { return nil }
        return SessionRecord(
            id: id, kind: kind, startedAt: startedAt, endedAt: endedAt,
            plannedSeconds: plannedSeconds, activeSeconds: activeSeconds,
            outcome: outcome, origin: Origin(rawValue: origin) ?? .manual)
    }
}

/// The session log, stored with SwiftData. `url == nil` keeps it in memory.
@MainActor
public final class SwiftDataSessionStore: SessionStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(url: URL?) throws {
        let configuration = url.map { ModelConfiguration(url: $0) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: StoredSession.self, configurations: configuration)
    }

    public func save(_ record: SessionRecord) {
        context.insert(StoredSession(record))
        try? context.save()
    }

    public func sessions(in interval: DateInterval) -> [SessionRecord] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.record)
    }

    public func earliestStart() -> Date? {
        var descriptor = FetchDescriptor<StoredSession>(sortBy: [SortDescriptor(\.startedAt)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.startedAt
    }
}
