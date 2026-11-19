import Foundation

/// Keeps the engine snapshot as a JSON file. A missing, empty or unreadable
/// file loads as nil, so a damaged file never stops the app from starting.
@MainActor
public final class FileSnapshotStore: SnapshotStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> EngineSnapshot? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(EngineSnapshot.self, from: data)
    }

    public func save(_ snapshot: EngineSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            // A failed checkpoint only weakens crash recovery; the timer keeps running.
        }
    }
}
