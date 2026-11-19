import AppKit
import FocusNowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var engine: TimerEngine!
    private var driver: TimerDriver!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let calendar = Calendar.autoupdatingCurrent
        let clock: () -> Date = { Date() }
        let dataDir = Self.dataDirectory()

        settings = SettingsStore(defaults: Self.defaults(), clock: clock, calendar: calendar)
        let sessions = Self.openSessionStore(at: dataDir.appendingPathComponent("sessions.store"))
        let settings = self.settings!
        engine = TimerEngine(
            settings: { settings.settings }, sessions: sessions,
            snapshots: FileSnapshotStore(url: dataDir.appendingPathComponent("engine-snapshot.json")),
            clock: clock, calendar: calendar)

        driver = TimerDriver(engine: engine)
        driver.start()

        statusItem = StatusItemController(engine: engine)
        // Temporary until the popover exists: click toggles the countdown.
        statusItem.onClick = { [weak self] in
            guard let engine = self?.engine else { return }
            switch engine.status {
            case .idle: engine.start()
            case .running: engine.pause()
            case .paused: engine.resume()
            }
        }

        if let dir = DebugSnapshots.directory {
            Task { await runSnapshotScript(DebugSnapshots(dir: dir)) }
        }
    }

    private func runSnapshotScript(_ snap: DebugSnapshots) async {
        await snap.wait(0.5)
        snap.note("idle: " + DebugSnapshots.describe(statusItem.button))
        engine.start()
        await snap.wait(0.6)
        snap.note("focus +0.6s: " + DebugSnapshots.describe(statusItem.button))
        await snap.wait(2.0)
        snap.note("focus +2.6s: " + DebugSnapshots.describe(statusItem.button))
        engine.pause()
        await snap.wait(0.6)
        snap.note("paused: " + DebugSnapshots.describe(statusItem.button))
        await snap.wait(1.5)
        snap.note("paused +1.5s: " + DebugSnapshots.describe(statusItem.button))
        engine.cancel()
        await snap.wait(0.6)
        snap.note("cancelled: " + DebugSnapshots.describe(statusItem.button))
        snap.finish()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.prepareForQuit()
    }

    // MARK: - Storage

    /// Set FOCUSNOW_DATA_DIR to run against a separate data folder and
    /// preferences (used when testing so real history stays untouched).
    private static let testDataDir = ProcessInfo.processInfo.environment["FOCUSNOW_DATA_DIR"]

    static func dataDirectory() -> URL {
        let dir: URL
        if let override = testDataDir {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("FocusNow", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func defaults() -> UserDefaults {
        guard testDataDir != nil else { return .standard }
        return UserDefaults(suiteName: "local.focusnow.app.testing") ?? .standard
    }

    /// Opens the session log. If it can't be opened, says so and keeps this
    /// run's sessions in memory rather than refusing to start.
    static func openSessionStore(at url: URL) -> SessionStore {
        do {
            return try SwiftDataSessionStore(url: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "FocusNow couldn't open its session history"
            alert.informativeText = "Sessions from this run won't be saved.\n\n\(error.localizedDescription)"
            alert.runModal()
            return InMemorySessionStore()
        }
    }
}
