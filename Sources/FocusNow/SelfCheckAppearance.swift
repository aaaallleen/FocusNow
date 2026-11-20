import AppKit
import FocusNowCore
import SwiftUI

/// The self-check's appearance phase: the light/dark mode reaches the window
/// and the popover but not the menu bar, and a colourway reaches every screen
/// without losing what's on it.
extension AppDelegate {
    func checkAppearance(_ snap: DebugSnapshots) async {
        snap.note("== appearance ==")
        engine.cancel()
        engine.skipBreak()
        closeAllWindows()
        await snap.wait(0.4)
        showTimer()
        await snap.wait(0.6)
        guard let window = windows.mainWindow, let frameView = window.contentView?.superview else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.4)
        func name(_ appearance: NSAppearance?) -> String { appearance.map { $0.isDark ? "dark" : "light" } ?? "none" }
        func shot(_ name: String) async {
            await snap.wait(0.2)
            snap.capture(frameView, as: name, scale: 1)
        }

        // Each mode: the window and the popover follow it, the menu bar doesn't.
        let system = name(NSApp.effectiveAppearance)
        let menubar = name(statusItem.button?.effectiveAppearance)
        statusItem.showPopover(fromClick: false) // doesn't activate the app
        await snap.wait(0.6)
        for mode in AppearanceMode.allCases {
            appearancePrefs.mode = mode
            await snap.wait(0.5)
            let want = mode == .system ? system : mode.rawValue
            snap.note("mode=\(mode) app=\(name(NSApp.effectiveAppearance)) window=\(name(window.effectiveAppearance)) " +
                "popover=\(name(statusItem.popoverWindow?.contentView?.effectiveAppearance)) " +
                "menubar=\(name(statusItem.button?.effectiveAppearance)) " +
                "(want window and popover \(want), menubar \(menubar))")
        }
        appearancePrefs.mode = .system
        statusItem.closePopover()
        await snap.wait(0.4)

        // A colourway change keeps what's on screen: here, last week's Stats.
        mainState.page = .stats
        statsModel.range = .week
        statsModel.pageBack()
        await snap.wait(0.5)
        let shown = statsModel.interval
        appearancePrefs.choosePreset("ocean")
        await snap.wait(0.5)
        snap.note("stats period kept=\(statsModel.interval == shown && statsModel.range == .week && mainState.page == .stats) " +
            "colorway=\(appearancePrefs.colorwayID) (want true ocean)")
        await shot("stats-ocean")
        statsModel.range = .day
        mainState.page = .timer
        await snap.wait(0.5)
        window.appearance = NSAppearance(named: .aqua)
        await shot("timer-ocean")
        window.appearance = NSAppearance(named: .darkAqua)
        await shot("timer-ocean-dark")
        window.appearance = nil

        // The menu bar timer during a break takes the break colour of the menu bar's mode.
        engine.nextFocusSecondsOverride = 2
        engine.start()
        await snap.wait(3.0)
        engine.nextFocusSecondsOverride = nil
        engine.acknowledge()
        statusItem.closePopover()
        engine.start() // the short break
        await snap.wait(0.6)
        appearancePrefs.choosePreset("rose")
        await snap.wait(0.6)
        let rose = Colorway.preset(id: "rose")!.palette
        var shownHex = "none"
        if let button = statusItem.button, button.attributedTitle.length > 0,
           let color = button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                shownHex = SRGBColor(color)?.hex ?? "unreadable"
            }
        }
        let wantHex = rose.rest(dark: statusItem.button?.effectiveAppearance.isDark ?? false).hex
        snap.note("menubar break kind=\(engine.active?.kind.rawValue ?? "none") color=\(shownHex) (want shortBreak \(wantHex))")
        snap.note("menubar: " + DebugSnapshots.describe(statusItem.button))

        engine.cancel()
        engine.skipBreak()
        appearancePrefs.choosePreset("teal")
        appearancePrefs.mode = .system
        await snap.wait(0.4)
    }
}
