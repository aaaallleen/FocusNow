import AppKit
import FocusNowCore

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

        // Choosing Flow: Start flow at 00:00, and nothing moves.
        let before = frames()
        engine.chooseFlow(true)
        await snap.wait(0.4)
        let after = frames()
        let found = snap.accessibilityFrame(of: TimerHeader.switchIdentifier, in: window) != nil
        snap.note("flow switch: chosen=\(engine.flowChosen) ringMoved=\(moved(before.ring, after.ring)) " +
            "mainMoved=\(moved(before.main, after.main)) label=\(engine.clockLabel) start=\(mainTitle()) " +
            "voiceover=\(found) (want true false false 00:00 Start flow true)")

        // Flowing: the switch is locked, Stop leads, and it counts up with no "+".
        engine.start()
        await snap.wait(1.2)
        snap.note("flow running: flowing=\(engine.isFlowing) canChoose=\(engine.canChooseFlow) main=\(mainTitle()) " +
            "label+=\(engine.clockLabel.hasPrefix("+")) (want true false Stop false)")

        engine.cancel()
        engine.chooseFlow(false)
        await snap.wait(0.4)
    }
}
