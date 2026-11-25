import AppKit
import FocusNowCore

/// The self-check's runover phase: Allow time to run over.
/// - the switch in Settings → Cycle, with its caption;
/// - the notification text at zero;
/// - a focus past zero keeps counting, shown as +m:ss, and Start break saves
///   it as one finished focus with its extra time;
/// - ten idle minutes (faked) end it at the last input;
/// - with the switch off, a focus finishes at zero as before.
extension AppDelegate {
    func checkRunOver(_ snap: DebugSnapshots) async {
        snap.note("== runover ==")
        fakeIdleSeconds = 0
        engine.cancel()
        engine.skipBreak()
        let checkStart = Date()
        func last() -> SessionRecord? {
            sessions.sessions(in: DateInterval(start: checkStart, end: .distantFuture)).last
        }
        func shortFocus() {
            engine.nextFocusSecondsOverride = 2
            engine.start()
            engine.nextFocusSecondsOverride = nil // a set length stays; only this session is short
        }
        func reset() async {
            engine.skipBreak()
            statusItem.closePopover()
            await snap.wait(0.6)
        }

        // The switch, in Settings → Cycle.
        mainState.settingsSection = .cycle
        showSettings()
        await snap.wait(0.6)
        if let window = windows.mainWindow {
            let caption = snap.containsText(SettingsView.runOverCaption, in: window)
            // A switch reports the checkbox role (subrole AXSwitch); VoiceOver says "switch".
            let spoken = snap.spoken(roles: ["AXCheckBox"], in: window).contains("AXCheckBox \"Allow time to run over\"")
            let pressed = await snap.press(accessibilityLabel: SettingsView.runOverSwitchIdentifier, in: window)
            await snap.wait(0.3)
            snap.note("runover switch: pressed=\(pressed) on=\(settings.settings.allowRunOver) caption=\(caption) " +
                "voiceover=\(spoken) (want true true true true)")
            if let content = window.contentView { snap.capture(content, as: "settings-cycle-run-over") }
        } else {
            snap.note("runover switch: no main window (want one)")
        }
        closeAllWindows()
        await snap.wait(0.4)

        let over = FinishAlerter.message(for: .focus, runningOver: true)
        snap.note("runover message: \(over.title) / \(over.body) " +
            "(want Focus time is up / The clock keeps running until you start your break.)")
        snap.note("plain message: \(FinishAlerter.message(for: .focus, runningOver: false).title) (want Focus session finished)")

        // A 2-second focus runs over and keeps counting.
        shortFocus()
        await snap.wait(3.5)
        snap.note("runover at zero: status=\(engine.status) over=\(engine.isRunningOver) " +
            "label+=\(engine.clockLabel.hasPrefix("+")) menubar+=\((statusItem.button?.title ?? "").hasPrefix(" +")) " +
            "attention=\(engine.needsAttention) popover=\(statusItem.popoverWindowVisible) " +
            "(want running true true true true true) label=\(engine.clockLabel)")

        // Start break saves one finished focus with the time past zero in it.
        if let popover = statusItem.popoverWindow {
            _ = await snap.press(accessibilityLabel: "Start break", in: popover)
        }
        await snap.wait(0.4)
        snap.note("runover start break: active=\(last()?.activeSeconds ?? -1) completed=\(last()?.outcome == .completed) " +
            "onBreak=\(engine.active?.kind.isBreak ?? false) (want ≥3 true true)")
        await reset()

        // Ten idle minutes end it at the last input, which was before zero here.
        shortFocus()
        await snap.wait(3.0)
        fakeIdleSeconds = TimerEngine.runOverIdleLimitSeconds
        await snap.wait(1.0)
        snap.note("runover idle: status=\(engine.status) breakNext=\(engine.nextKind.isBreak) " +
            "active=\(last()?.activeSeconds ?? -1) attention=\(engine.needsAttention) (want idle true 2 true)")
        fakeIdleSeconds = 0
        await reset()

        // Carrying on: Escape (or a click elsewhere) closes the popover the zero
        // opened and stops the flash, while the clock keeps counting.
        shortFocus()
        await snap.wait(3.0)
        snap.note("runover popover: closesOnOutsideClick=\(statusItem.closesOnOutsideClick) (want true)")
        if let popover = statusItem.popoverWindow {
            await snap.postKey(53, characters: "\u{1b}", in: popover)
        }
        await snap.wait(0.6)
        snap.note("runover escape: visible=\(statusItem.popoverWindowVisible) attention=\(engine.needsAttention) " +
            "over=\(engine.isRunningOver) flashing=\(statusItem.isFlashing) (want false false true false)")
        await reset()

        // Switched off: a focus finishes at zero, as before.
        settings.settings.allowRunOver = false
        shortFocus()
        await snap.wait(3.0)
        snap.note("runover off: status=\(engine.status) over=\(engine.isRunningOver) (want idle false)")
        await reset()
    }
}
