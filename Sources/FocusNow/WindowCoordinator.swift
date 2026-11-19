import AppKit
import SwiftUI

/// Owns the main window (Timer and Stats pages), the settings window and the
/// Dock icon: the icon shows while either window is open and hides when the
/// last one closes, leaving the app in the menu bar.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let makeMain: () -> AnyView
    private let makeSettings: () -> AnyView
    private(set) var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(makeMain: @escaping () -> AnyView, makeSettings: @escaping () -> AnyView) {
        self.makeMain = makeMain
        self.makeSettings = makeSettings
    }

    var isMainVisible: Bool { mainWindow?.isVisible ?? false }
    var isSettingsVisible: Bool { settingsWindow?.isVisible ?? false }
    var settingsContentView: NSView? { settingsWindow?.contentView }

    func showMain() {
        if mainWindow == nil {
            let window = makeWindow(title: "FocusNow", content: makeMain(), resizable: true)
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 560))
            window.contentMinSize = NSSize(width: 640, height: 480)
            window.setFrameAutosaveName("FocusNowMainWindow")
            if !window.setFrameUsingName("FocusNowMainWindow") { window.center() }
            mainWindow = window
        }
        present(mainWindow!)
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
        if resizable {
            // Lets the SwiftUI toolbar (the Timer | Stats switch) reach the window.
            controller.sceneBridgingOptions = [.toolbars]
        } else {
            controller.sizingOptions = [.preferredContentSize]
        }
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
        let othersOpen = [mainWindow, settingsWindow].contains { window in
            guard let window, window !== closing else { return false }
            return window.isVisible || window.isMiniaturized
        }
        if !othersOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
