import AppKit
import FocusNowCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var settings: SettingsStore!
    private(set) var sessions: SessionStore!
    private(set) var engine: TimerEngine!
    private(set) var statusItem: StatusItemController!
    private(set) var alerter: FinishAlerter!
    private var driver: TimerDriver!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let calendar = Calendar.autoupdatingCurrent
        let clock: () -> Date = { Date() }
        let dataDir = Self.dataDirectory()

        let settings = SettingsStore(defaults: Self.defaults(), clock: clock, calendar: calendar)
        self.settings = settings
        sessions = Self.openSessionStore(at: dataDir.appendingPathComponent("sessions.store"))
        engine = TimerEngine(
            settings: { settings.settings }, sessions: sessions,
            snapshots: FileSnapshotStore(url: dataDir.appendingPathComponent("engine-snapshot.json")),
            clock: clock, calendar: calendar)

        driver = TimerDriver(engine: engine)
        driver.start()

        alerter = FinishAlerter(settings: settings)
        statusItem = StatusItemController(engine: engine)
        statusItem.setPopoverContent(makePopoverController())

        engine.onFinish = { [weak self] kind in
            guard let self else { return }
            statusItem.showPopover(fromClick: false)
            alerter.sessionFinished(kind)
        }
        alerter.onNotificationClicked = { [weak self] in
            self?.engine.acknowledge()
            self?.statusItem.showPopover(fromClick: true)
        }

        if let dir = DebugSnapshots.directory {
            alerter.isSelfCheck = true
            Task { await runSelfCheck(DebugSnapshots(dir: dir)) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.prepareForQuit()
    }

    func makePopoverController() -> NSViewController {
        let controller = NSHostingController(rootView: PopoverView(
            engine: engine, settings: settings,
            onAction: { [weak self] control in
                guard let self else { return }
                statusItem.popoverWasUsed()
                if control == .startFocus || control == .startBreak, DebugSnapshots.directory == nil {
                    alerter.requestAuthorizationIfNeeded()
                }
            },
            onStats: { [weak self] in self?.showStats() },
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }))
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    func showStats() {}

    func showSettings() {}

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
