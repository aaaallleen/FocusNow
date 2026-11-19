import AppKit
import FocusNowCore
import SwiftUI

/// The self-check script run when FOCUSNOW_SNAPSHOT_DIR is set (see DebugSnapshots).
extension AppDelegate {
    func runSelfCheck(_ snap: DebugSnapshots) async {
        await snap.wait(0.5)
        let popover = { PopoverView(engine: self.engine, settings: self.settings) }
        func menubar(_ label: String) { snap.note("\(label): " + DebugSnapshots.describe(statusItem.button)) }
        func state(_ label: String) {
            snap.note("\(label): status=\(engine.status) phase=\"\(engine.phaseLabel)\" controls=\(engine.controls) " +
                "remaining=\(engine.remainingSeconds) attention=\(engine.needsAttention) " +
                "today=\(engine.todayFocusSeconds()) popoverVisible=\(statusItem.popoverWindowVisible) " +
                "flashing=\(statusItem.isFlashing)")
        }

        // Idle, and the one-off length adjuster.
        state("idle")
        snap.render(popover(), as: "popover-idle")
        snap.render(popover(), as: "popover-idle-dark", dark: true)
        engine.adjustNextFocus(byMinutes: 5)
        state("after +5")
        snap.render(popover(), as: "popover-idle-45")
        engine.adjustNextFocus(byMinutes: -5)

        // Clicking the item toggles the popover.
        statusItem.clicked()
        await snap.wait(0.1)
        snap.note("click 1: popoverVisible=\(statusItem.popoverWindowVisible) behavior=\(statusItem.popoverBehavior.rawValue) active=\(NSApp.isActive)")
        await snap.wait(1.0)
        statusItem.clicked()
        snap.note("click 2: popoverVisible=\(statusItem.popoverWindowVisible)")

        // A 3-second focus session to exercise the finish flow.
        engine.nextFocusSecondsOverride = 3
        engine.start()
        await snap.wait(1.2)
        state("focus running")
        menubar("menubar focus")
        snap.render(popover(), as: "popover-focus-running")
        snap.render(popover(), as: "popover-focus-running-dark", dark: true)
        engine.pause()
        await snap.wait(0.3)
        state("focus paused")
        snap.render(popover(), as: "popover-focus-paused")
        engine.resume()
        await snap.wait(3.0)
        state("focus finished")
        snap.note("sound would play: \(settings.settings.soundOn && NSSound(named: FinishAlerter.soundName) != nil)")
        snap.note("finished popover behavior=\(statusItem.popoverBehavior.rawValue) " +
            "(0=applicationDefined 1=transient) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        menubar("menubar finished")
        var alphas: [String] = []
        for _ in 0..<5 {
            alphas.append(String(format: "%.2f", statusItem.button?.alphaValue ?? -1))
            await snap.wait(0.3)
        }
        snap.note("flash alpha samples: \(alphas.joined(separator: " "))")
        snap.render(popover(), as: "popover-finished")

        // Clicking the item stops the flash and leaves the break waiting.
        statusItem.clicked()
        await snap.wait(0.1)
        state("after click")
        menubar("menubar after click")

        // A break.
        engine.start()
        await snap.wait(1.2)
        state("break running")
        menubar("menubar break")
        snap.render(popover(), as: "popover-break-running")
        snap.render(popover(), as: "popover-break-running-dark", dark: true)
        engine.skipBreak()
        state("after skip")
        snap.render(popover(), as: "popover-idle-after-break")

        // Ending early under a minute logs nothing; cancelling logs nothing.
        let before = engine.todayFocusSeconds()
        engine.start(); await snap.wait(1.1); engine.endEarly()
        engine.start(); await snap.wait(1.1); engine.cancel()
        snap.note("short end early + cancel: today before=\(before) after=\(engine.todayFocusSeconds()) " +
            "phase=\"\(engine.phaseLabel)\"")

        // Sleep pauses a running session.
        engine.start()
        await snap.wait(1.1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await snap.wait(0.3)
        state("after willSleep")
        engine.cancel()

        // Quit with a session running: applicationWillTerminate must checkpoint it.
        engine.start()
        await snap.wait(1.2)
        snap.note("quitting with a running session")
        snap.finish()
    }
}
