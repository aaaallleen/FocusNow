import AppKit
import FocusNowCore
import SwiftUI

/// The self-check script run when FOCUSNOW_SNAPSHOT_DIR is set (see DebugSnapshots).
extension AppDelegate {
    /// FOCUSNOW_SELFCHECK picks phases (comma-separated: popover, stats); default is all.
    func runSelfCheck(_ snap: DebugSnapshots) async {
        let phases = ProcessInfo.processInfo.environment["FOCUSNOW_SELFCHECK"]?
            .split(separator: ",").map(String.init) ?? ["popover", "stats"]
        await snap.wait(0.5)
        snap.note("launched from \(Bundle.main.bundlePath): policy=\(policyName) statsVisible=\(windows.isStatsVisible) " +
            "icon=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "none") " +
            "iconFile=\(Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil)")
        if phases.contains("stats") { await checkStats(snap) }
        if phases.contains("popover") { await checkPopover(snap) }
        snap.finish()
    }

    var policyName: String {
        switch NSApp.activationPolicy() {
        case .regular: "regular (Dock icon)"
        case .accessory: "accessory (no Dock icon)"
        default: "prohibited"
        }
    }

    func checkStats(_ snap: DebugSnapshots) async {
        snap.note("== stats ==")
        snap.note("launch: policy=\(policyName) statsVisible=\(windows.isStatsVisible) loginItem=\(launchedAsLoginItemForCheck)")
        seedHistory()
        statsModel.reload()
        func tiles() -> String {
            StatsRange.allCases.map { "\($0)=\(TimeFormat.duration(statsModel.tiles[$0]?.focusSeconds ?? 0))/\(statsModel.tiles[$0]?.sessionCount ?? 0)" }
                .joined(separator: " ")
        }
        snap.note("tiles: \(tiles())")
        let view = { StatsView(model: self.statsModel).frame(width: 760, height: 560) }
        snap.render(view(), as: "stats-week")
        snap.render(view(), as: "stats-week-dark", dark: true)
        snap.note("week: buckets=\(statsModel.buckets.count) summary=\(statsModel.summary) listed=\(statsModel.listedSessions.count)")
        for range in [StatsRange.month, .year, .allTime, .day] {
            statsModel.range = range
            snap.render(view(), as: "stats-\(range)")
            snap.note("\(range): buckets=\(statsModel.buckets.count) canBack=\(statsModel.canPageBack) canForward=\(statsModel.canPageForward) listed=\(statsModel.listedSessions.count)")
        }
        statsModel.range = .week
        let tuesday = statsModel.buckets[1].id
        statsModel.selectedBucketID = tuesday
        snap.render(view(), as: "stats-week-selected")
        windows.showStats()
        await snap.wait(0.5)
        if let content = NSApp.windows.first(where: { $0.title == "Focus Stats" })?.contentView {
            snap.capture(content, as: "stats-window-live", scale: 1)
        }
        snap.note("selected Tuesday: listed=\(statsModel.listedSessions.count) listInterval=\(statsModel.listInterval.start)")
        statsModel.selectedBucketID = nil
        statsModel.pageBack()
        snap.render(view(), as: "stats-previous-week")
        snap.note("previous week: canForward=\(statsModel.canPageForward) listed=\(statsModel.listedSessions.count) tiles unchanged=\(tiles())")
        statsModel.range = .week

        // Closing the last window hides the Dock icon; the app stays in the menu bar.
        closeAllWindows()
        await snap.wait(0.5)
        snap.note("after close: policy=\(policyName) statsVisible=\(windows.isStatsVisible) running=true")

        // Launching again from outside (as Spotlight does) brings Stats back.
        try? "ready".write(to: snap.directory.appendingPathComponent("ready-for-reopen"), atomically: true, encoding: .utf8)
        for _ in 0..<40 where !windows.isStatsVisible { await snap.wait(0.25) }
        snap.note("after external launch: policy=\(policyName) statsVisible=\(windows.isStatsVisible)")
        closeAllWindows()
        await snap.wait(0.5)

        // The popover's Stats button.
        statusItem.showPopover(fromClick: true)
        await snap.wait(0.3)
        showStats()
        await snap.wait(0.3)
        snap.note("popover Stats: popoverVisible=\(statusItem.popoverWindowVisible) statsVisible=\(windows.isStatsVisible) policy=\(policyName)")

        // A session saved while the window is open shows up in it.
        let before = statsModel.tiles[.day]?.sessionCount ?? -1
        engine.nextFocusSecondsOverride = 2
        engine.start()
        await snap.wait(3.0)
        engine.acknowledge()
        statusItem.closePopover()
        await snap.wait(0.2)
        snap.note("live refresh: today sessions before=\(before) after=\(statsModel.tiles[.day]?.sessionCount ?? -1)")
        closeAllWindows()
        await snap.wait(0.3)
    }

    private func closeAllWindows() {
        for window in NSApp.windows where window.isVisible && window.title.isEmpty == false {
            window.performClose(nil)
        }
    }

    /// About six weeks of plausible history, so the stats window has something to show.
    private func seedHistory() {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        for back in 1...45 {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let weekday = calendar.component(.weekday, from: day)
            let count = (weekday == 1 || weekday == 7) ? back % 2 : 3 + back % 4
            var start = calendar.date(byAdding: .hour, value: 9, to: day)!
            for n in 0..<count {
                let early = (back + n) % 7 == 0
                let length = early ? 900 + back * 13 : 2400
                sessions.save(SessionRecord(
                    kind: .focus, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(length)),
                    plannedSeconds: 2400, activeSeconds: length, outcome: early ? .endedEarly : .completed))
                start = start.addingTimeInterval(TimeInterval(length + 300 + n * 600))
            }
        }
        // Two finished sessions earlier today.
        for (hour, length) in [(9, 2400), (10, 1500)] {
            let start = calendar.date(byAdding: .minute, value: hour * 60 + 5, to: today)!
            guard start < Date() else { continue }
            sessions.save(SessionRecord(
                kind: .focus, startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(length)),
                plannedSeconds: 2400, activeSeconds: length, outcome: length < 2400 ? .endedEarly : .completed))
        }
    }

    func checkPopover(_ snap: DebugSnapshots) async {
        snap.note("== popover ==")
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
    }
}
