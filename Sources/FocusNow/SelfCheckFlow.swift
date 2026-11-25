import AppKit
import FocusNowCore
import SwiftUI

/// The self-check's flow phase:
/// - the Focus | Flow switch at the top of the Timer page: choosing Flow moves
///   neither the ring nor the main button, and offers Start flow at 00:00;
/// - while a flow runs, the switch is locked, Stop is the main button, and the
///   digits count up with no "+".
extension AppDelegate {
    func checkFlow(_ snap: DebugSnapshots) async {
        snap.note("== flow ==")
        engine.cancel()
        engine.skipBreak()
        engine.chooseFlow(false)
        fakeIdleSeconds = 0
        showTimer()
        await snap.wait(0.6)
        guard let window = windows.mainWindow else {
            snap.note("flow: no main window (want one)")
            return
        }
        func mainTitle() -> String { TimerControlsRow.title(for: engine.controlRows.main) }
        func frames() -> (ring: NSRect?, main: NSRect?) {
            (visibleRing(snap, in: window), snap.accessibilityFrame(of: mainTitle(), in: window))
        }
        func moved(_ a: NSRect?, _ b: NSRect?) -> Bool {
            guard let a, let b else { return true }
            return [a.minX - b.minX, a.maxX - b.maxX, a.minY - b.minY, a.maxY - b.maxY].contains { abs($0) > 0.5 }
        }

        // A length typed into the digits, then Flow chosen: what was typed is
        // kept, as every other control on the surface keeps it.
        if await snap.press(accessibilityLabel: TimerRing.digitsIdentifier, in: window), window.firstResponder is NSText {
            await snap.typeIntoFocusedField("50", in: window)
            let pressed = await snap.press(accessibilityLabel: "Flow", in: window)
            await snap.wait(0.3)
            let chose = engine.flowChosen
            engine.chooseFlow(false)
            await snap.wait(0.3)
            snap.note("flow switch keeps typing: pressed=\(pressed) chose=\(chose) next=\(engine.remainingSeconds / 60) " +
                "(want true true 50)")
        } else {
            snap.note("flow switch keeps typing: the digits did not become a field (want a field)")
        }
        engine.setNextFocus(minutes: 40)
        window.makeFirstResponder(nil)
        await snap.wait(0.4)

        // Choosing Flow: Start flow at 00:00, and nothing moves.
        let before = frames()
        engine.chooseFlow(true)
        await snap.wait(0.4)
        let after = frames()
        let found = snap.accessibilityFrame(of: TimerHeader.switchIdentifier, in: window) != nil
        snap.note("flow switch: chosen=\(engine.flowChosen) ringMoved=\(moved(before.ring, after.ring)) " +
            "mainMoved=\(moved(before.main, after.main)) label=\(engine.clockLabel) start=\(mainTitle()) " +
            "voiceover=\(found) (want true false false 00:00 Start flow true)")
        snap.render(PopoverView(engine: engine, settings: settings, appearance: appearancePrefs), as: "popover-flow-idle")

        // Flowing: the switch is locked, Stop leads, and it counts up with no "+".
        engine.start()
        await snap.wait(1.2)
        snap.note("flow running: flowing=\(engine.isFlowing) canChoose=\(engine.canChooseFlow) main=\(mainTitle()) " +
            "label+=\(engine.clockLabel.hasPrefix("+")) (want true false Stop false)")

        // The menu bar counts up too, with no "+".
        await snap.wait(1.3)
        let title = statusItem.button?.title ?? ""
        snap.note("flow menubar: plus=\(title.hasPrefix(" +")) counting=\(title.hasPrefix(" 00:0")) (want false true) title=\"\(title)\"")

        // Stop: under a minute, nothing is saved, and it's back to idle.
        let checkStart = Date().addingTimeInterval(-10)
        func saved() -> Int { sessions.sessions(in: DateInterval(start: checkStart, end: .distantFuture)).count }
        let savedBefore = saved()
        engine.stop()
        snap.note("flow stop: saved=\(saved() - savedBefore) status=\(engine.status) (want 0 idle)")

        // Ten idle minutes (faked) stop a flow without a flash.
        engine.start()
        await snap.wait(1.0)
        fakeIdleSeconds = TimerEngine.runOverIdleLimitSeconds
        await snap.wait(1.0)
        snap.note("flow idle: status=\(engine.status) attention=\(engine.needsAttention) (want idle false)")
        fakeIdleSeconds = 0

        // Stats lists a flow as "flow".
        let flowStart = Date().addingTimeInterval(-3200)
        sessions.save(SessionRecord(kind: .focus, startedAt: flowStart, endedAt: flowStart.addingTimeInterval(3120),
                                    plannedSeconds: 0, activeSeconds: 3120, outcome: .completed))
        calendarPrefs.statsDisplay = .chart
        statsModel.range = .day
        statsModel.reload()
        showStats()
        await snap.wait(0.8)
        let listed = windows.mainWindow.map { snap.containsText("52m flow", in: $0) } ?? false
        snap.note("flow stats row: \(listed) (want true)")
        showTimer()
        await snap.wait(0.4)

        await checkFlowSecondHour(snap)

        // Choosing on the switch in a popover a finish opened counts as using
        // it, as −/+ do: another app coming forward then closes it.
        engine.cancel()
        engine.skipBreak()
        engine.chooseFlow(false)
        statusItem.showPopover(fromClick: false)
        await snap.wait(0.5)
        if let popover = statusItem.popoverWindow {
            _ = await snap.press(accessibilityLabel: "Flow", in: popover)
        }
        let other = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular
        }
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
            userInfo: other.map { [NSWorkspace.applicationUserInfoKey: $0] })
        await snap.wait(0.6)
        snap.note("flow finish-opened, then Flow chosen, another app forward: visible=\(statusItem.popoverWindowVisible) " +
            "chosen=\(engine.flowChosen) (want false true)")
        statusItem.closePopover()
        await snap.wait(0.6)

        engine.cancel()
        engine.chooseFlow(false)
        await snap.wait(0.4)
    }

    /// 1:24:30 into a flow (on a scratch engine with its own clock): the ring
    /// is full in the focus colour, with the second hour filling over it in the
    /// second colour, so 12 o'clock shows the second colour and 9 o'clock the first.
    private func checkFlowSecondHour(_ snap: DebugSnapshots) async {
        final class Clock { var now = Date() }
        let clock = Clock()
        let scratch = TimerEngine(
            settings: { TimerSettings() }, sessions: InMemorySessionStore(), snapshots: InMemorySnapshotStore(),
            clock: { clock.now }, calendar: .current)
        scratch.chooseFlow(true)
        scratch.start()
        for _ in 0..<5070 {
            clock.now = clock.now.addingTimeInterval(1)
            scratch.tick()
        }
        let palette = appearancePrefs.palette
        let window = NSWindow(
            contentRect: NSRect(x: 140, y: 140, width: 220, height: 220),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TimerRing(engine: scratch, diameter: 150)
            .environment(\.palette, palette).frame(width: 220, height: 220))
        window.orderFront(nil)
        await snap.wait(0.6)
        guard let digits = snap.accessibilityFrame(of: TimerRing.digitsIdentifier, in: window) else {
            snap.note("flow second hour: no ring (want one)")
            window.close()
            return
        }
        // The stroke's middle: 75 pt out from the centre, less half its 8 pt width.
        let centre = NSPoint(x: digits.midX, y: digits.midY), radius: CGFloat = 71
        func patch(degreesFromTop a: CGFloat) -> NSRect {
            let t = a * .pi / 180
            return NSRect(x: centre.x + radius * sin(t) - 1.5, y: centre.y + radius * cos(t) - 1.5, width: 3, height: 3)
        }
        let dark = window.effectiveAppearance.isDark
        let first = palette.focus(dark: dark), second = first.secondLapShade()
        func name(_ colour: SRGBColor?) -> String {
            guard let colour else { return "none" }
            func distance(_ a: SRGBColor, _ b: SRGBColor) -> Double {
                pow(a.red - b.red, 2) + pow(a.green - b.green, 2) + pow(a.blue - b.blue, 2)
            }
            let (d1, d2) = (distance(colour, first), distance(colour, second))
            if min(d1, d2) > 0.05 { return "other(\(colour.hex))" }
            return d1 < d2 ? "focus" : "second"
        }
        let top = name(snap.averageColour(of: patch(degreesFromTop: 10), in: window))
        let left = name(snap.averageColour(of: patch(degreesFromTop: 270), in: window))
        snap.note("flow second hour: top=\(top) left=\(left) (want second focus) label=\(scratch.clockLabel)")
        snap.render(PopoverView(engine: scratch, settings: settings, appearance: appearancePrefs), as: "popover-flow-second-hour")
        snap.render(PopoverView(engine: scratch, settings: settings, appearance: appearancePrefs),
                    as: "popover-flow-second-hour-dark", dark: true)
        window.close()
    }
}
