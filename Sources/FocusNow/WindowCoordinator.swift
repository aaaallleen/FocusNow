import AppKit
import SwiftUI

/// Owns the stats and settings windows and the Dock icon: the icon shows while
/// either window is open and hides when the last one closes, leaving the app in
/// the menu bar.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let makeStats: () -> AnyView
    private let makeSettings: () -> AnyView
    private var statsWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(makeStats: @escaping () -> AnyView, makeSettings: @escaping () -> AnyView) {
        self.makeStats = makeStats
        self.makeSettings = makeSettings
    }

    var isStatsVisible: Bool { statsWindow?.isVisible ?? false }
    var isSettingsVisible: Bool { settingsWindow?.isVisible ?? false }

    func showStats() {
        if statsWindow == nil {
            let window = makeWindow(title: "Focus Stats", content: makeStats(), resizable: true)
            window.setContentSize(NSSize(width: 760, height: 560))
            window.contentMinSize = NSSize(width: 640, height: 480)
            window.setFrameAutosaveName("FocusStatsWindow")
            if !window.setFrameUsingName("FocusStatsWindow") { window.center() }
            statsWindow = window
        }
        present(statsWindow!)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = makeWindow(title: "Settings", content: makeSettings(), resizable: false)
            window.center()
            settingsWindow = window
        }
        present(settingsWindow!)
    }

    private func makeWindow(title: String, content: AnyView, resizable: Bool) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        if !resizable { controller.sizingOptions = [.preferredContentSize] }
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let othersOpen = [statsWindow, settingsWindow].contains { window in
            guard let window, window !== closing else { return false }
            return window.isVisible || window.isMiniaturized
        }
        if !othersOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
