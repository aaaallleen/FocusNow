import AppKit
import FocusNowCore
import SwiftUI

/// Owns the main window (Timer, Stats and Settings pages) and the Dock icon:
/// the icon shows while the window is open and hides when it closes, leaving
/// the app in the menu bar.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let makeMain: () -> AnyView
    /// False while testing: the window's place lives in the app's real
    /// preferences, which a test run must not touch.
    private let savesWindowPlace: Bool
    private(set) var mainWindow: NSWindow?

    private static let mainAutosaveName = "FocusNowMainWindow"
    /// The Stats window the main window replaced.
    private static let statsAutosaveName = "FocusStatsWindow"

    init(makeMain: @escaping () -> AnyView, savesWindowPlace: Bool) {
        self.makeMain = makeMain
        self.savesWindowPlace = savesWindowPlace
    }

    var isMainVisible: Bool { mainWindow?.isVisible ?? false }

    func showMain() {
        if mainWindow == nil {
            let window = makeWindow(title: "FocusNow", content: makeMain())
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 560))
            window.contentMinSize = NSSize(width: 640, height: 480)
            if savesWindowPlace {
                // The first time after upgrading, open where the Stats window was.
                WindowFrames.carryOver(from: Self.statsAutosaveName, to: Self.mainAutosaveName, in: .standard)
                window.setFrameAutosaveName(Self.mainAutosaveName)
                if !window.setFrameUsingName(Self.mainAutosaveName) { window.center() }
            } else {
                window.center()
            }
            mainWindow = window
        }
        present(mainWindow!)
    }

    private func makeWindow(title: String, content: AnyView) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        // Lets the SwiftUI toolbar (the Timer | Stats | Settings switch) reach the window.
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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
        // A field being typed in commits when it loses focus; closing alone
        // wouldn't take it away, and the typed value would be lost.
        (notification.object as? NSWindow)?.makeFirstResponder(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}
