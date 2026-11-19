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
    private(set) var statsModel: StatsViewModel!
    private(set) var windows: WindowCoordinator!
    let mainState = MainWindowState()
    private var driver: TimerDriver!
    private var launchedAsLoginItem = false
    var launchedAsLoginItemForCheck: Bool { launchedAsLoginItem }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A login-item launch starts quietly in the menu bar; any other launch opens the Timer page.
        if let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication {
            launchedAsLoginItem =
                event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        }
    }

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

        let statsModel = StatsViewModel(
            sessions: sessions, goal: { settings.goal(on: $0) }, clock: clock, calendar: calendar)
        self.statsModel = statsModel
        let mainState = self.mainState
        let engine = self.engine!
        windows = WindowCoordinator(
            makeMain: { [weak self] in
                AnyView(MainWindowView(
                    state: mainState, engine: engine, settings: settings, statsModel: statsModel,
                    onAction: { control in self?.windowTimerWasUsed(control) }))
            },
            makeSettings: { AnyView(SettingsView(settings: settings)) })
        NSApp.mainMenu = makeMainMenu()
        reloadStatsWhenSessionsChange()
        reloadStatsWhenSettingsChange()
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statsModel.reload() }
        }

        if !launchedAsLoginItem {
            showTimer()
        }

        if let dir = DebugSnapshots.directory {
            alerter.isSelfCheck = true
            Task { await runSelfCheck(DebugSnapshots(dir: dir)) }
        }
    }

    /// Spotlight, Launchpad or Finder while already running: bring the Timer page back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTimer()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Shown while a window is open (the app is a regular app then).
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "FocusNow")
        appMenu.addItem(withTitle: "About FocusNow",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FocusNow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FocusNow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "FocusNow", action: nil, keyEquivalent: "").submenu = appMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(.separator())
        let timerItem = windowMenu.addItem(withTitle: "Timer", action: #selector(openTimer), keyEquivalent: "1")
        timerItem.target = self
        let statsItem = windowMenu.addItem(withTitle: "Stats", action: #selector(openStats), keyEquivalent: "2")
        statsItem.target = self
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return main
    }

    @objc private func openSettings() { showSettings() }

    @objc private func openTimer() { showTimer() }

    @objc private func openStats() { showStats() }

    /// Starting from the window asks for notification permission, as the popover does.
    private func windowTimerWasUsed(_ control: TimerControl) {
        if control == .startFocus || control == .startBreak, DebugSnapshots.directory == nil {
            alerter.requestAuthorizationIfNeeded()
        }
    }

    /// A changed goal changes the stats (the goal line and today's tile).
    private func reloadStatsWhenSettingsChange() {
        withObservationTracking {
            _ = settings.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.statsModel.reload()
                self?.reloadStatsWhenSettingsChange()
            }
        }
    }

    private func reloadStatsWhenSessionsChange() {
        withObservationTracking {
            _ = engine.savedSessionCount
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.statsModel.reload()
                self?.reloadStatsWhenSessionsChange()
            }
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

    func showTimer() {
        statusItem.closePopover()
        mainState.page = .timer
        windows.showMain()
    }

    func showStats() {
        statusItem.closePopover()
        statsModel.reload()
        mainState.page = .stats
        windows.showMain()
    }

    func showSettings() {
        statusItem.closePopover()
        windows.showSettings()
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
