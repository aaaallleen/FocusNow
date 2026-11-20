import AppKit
import FocusNowCore
import ServiceManagement
import SwiftUI

/// The self-check script run when FOCUSNOW_SNAPSHOT_DIR is set (see DebugSnapshots).
extension AppDelegate {
    /// FOCUSNOW_SELFCHECK picks phases (comma-separated: popover, stats); default is all.
    func runSelfCheck(_ snap: DebugSnapshots) async {
        let phases = ProcessInfo.processInfo.environment["FOCUSNOW_SELFCHECK"]?
            .split(separator: ",").map(String.init) ?? ["stats", "settings", "calendar", "appearance", "timer", "digits", "commits", "menubar", "outside", "popover"]
        await snap.wait(0.5)
        snap.note("launched from \(Bundle.main.bundlePath): policy=\(policyName) mainVisible=\(windows.isMainVisible) page=\(mainState.page) " +
            "icon=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "none") " +
            "iconFile=\(Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil)")
        if phases.contains("stats") { await checkStats(snap) }
        if phases.contains("settings") { await checkSettings(snap) }
        if phases.contains("calendar") { await checkCalendar(snap) }
        if phases.contains("appearance") { await checkAppearance(snap) }
        if phases.contains("timer") { await checkTimer(snap) }
        if phases.contains("digits") { await checkDigits(snap) }
        if phases.contains("commits") { await checkCommits(snap) }
        if phases.contains("persist") {
            let s = settings.settings
            snap.note("after relaunch: focus=\(s.focusMinutes) goal=\(TimeFormat.duration(s.dailyGoalSeconds)) sound=\(s.soundOn) " +
                "idleRemaining=\(engine.remainingSeconds) goalHistory=\(settings.goalHistory.count) " +
                "loginItemStatus=\(SMAppService.mainApp.status.rawValue) statsDisplay=\(calendarPrefs.statsDisplay) " +
                "mode=\(appearancePrefs.mode) colorway=\(appearancePrefs.colorwayID)")
        }
        if phases.contains("menubar") { await checkMenuBar(snap) }
        if phases.contains("outside") { await checkOutside(snap) }
        // Last: it quits with a session running, for the persist phase's relaunch.
        if phases.contains("popover") { await checkPopover(snap) }
        snap.finish()
    }

    /// The popover closes on a click elsewhere even though macOS may refuse to
    /// make the app active (it usually does when another app is in use).
    func checkOutside(_ snap: DebugSnapshots) async {
        snap.note("== outside ==")
        engine.cancel()
        engine.skipBreak() // idle with a focus next, so the digits can be typed into
        windows.showMain()
        await snap.wait(0.4)
        func visible() -> Bool { statusItem.popoverWindowVisible }
        func anotherAppComesForward() async {
            let other = NSWorkspace.shared.runningApplications.first {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular
            }
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
                userInfo: other.map { [NSWorkspace.applicationUserInfoKey: $0] })
            await snap.wait(0.6)
        }

        statusItem.clicked(); await snap.wait(0.5)
        snap.note("click-opened: visible=\(visible()) active=\(NSApp.isActive)")
        await anotherAppComesForward()
        snap.note("click-opened, another app forward: visible=\(visible()) (want false)")
        statusItem.closePopover(); await snap.wait(0.6)

        statusItem.clicked(); await snap.wait(0.5)
        if let popover = statusItem.popoverWindow, let view = popover.contentView {
            await snap.postClick(at: NSPoint(x: view.bounds.midX, y: view.bounds.maxY - 12), in: popover)
        }
        snap.note("click-opened, click inside it: visible=\(visible()) (want true)")
        if let main = windows.mainWindow {
            await snap.postClick(at: NSPoint(x: 12, y: 12), in: main)
        }
        snap.note("click-opened, click in the main window: visible=\(visible()) (want false)")
        statusItem.closePopover(); await snap.wait(0.6)

        statusItem.showPopover(fromClick: false); await snap.wait(0.5)
        await anotherAppComesForward()
        snap.note("finish-opened, another app forward: visible=\(visible()) (want true)")
        statusItem.closePopover(); await snap.wait(0.6)

        statusItem.clicked(); await snap.wait(0.6)
        statusItem.clicked(); await snap.wait(0.1)
        statusItem.clicked(); await snap.wait(0.9)
        snap.note("clicked again right after closing: visible=\(visible()) (want true)")
        statusItem.closePopover(); await snap.wait(0.6)

        // A click on the menu bar item toggles it closed through the item alone;
        // were the click also counted as outside, the popover would reopen.
        statusItem.clicked(); await snap.wait(0.5)
        if let itemWindow = statusItem.button?.window, let button = statusItem.button {
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            await snap.postClick(at: center, in: itemWindow)
        }
        await snap.wait(0.8)
        snap.note("click-opened, click on the item: visible=\(visible()) (want false)")
        statusItem.closePopover(); await snap.wait(0.6)

        // Escape closes a clicked-open popover, but while typing it only drops the edit.
        statusItem.clicked(); await snap.wait(0.5)
        if let popover = statusItem.popoverWindow {
            _ = await snap.press(accessibilityLabel: TimerRing.digitsIdentifier, in: popover)
            await snap.postKey(53, characters: "\u{1b}", in: popover)
            snap.note("escape while typing: visible=\(visible()) editing=\(popover.firstResponder is NSText) (want true false)")
            await snap.postKey(53, characters: "\u{1b}", in: popover)
            snap.note("escape: visible=\(visible()) (want false)")
        }
        statusItem.closePopover(); await snap.wait(0.6)
        statusItem.showPopover(fromClick: false); await snap.wait(0.5)
        if let popover = statusItem.popoverWindow {
            await snap.postKey(53, characters: "\u{1b}", in: popover)
        }
        snap.note("finish-opened, escape: visible=\(visible()) (want true)")
        statusItem.closePopover(); await snap.wait(0.6)

        // −/+ in a popover a finish opened count as using it, like Start does.
        engine.cancel()
        engine.skipBreak()
        statusItem.showPopover(fromClick: false); await snap.wait(0.5)
        if let popover = statusItem.popoverWindow {
            _ = await snap.press(accessibilityLabel: "Five minutes shorter", in: popover)
        }
        await anotherAppComesForward()
        snap.note("finish-opened, then − pressed, another app forward: visible=\(visible()) (want false)")
        statusItem.closePopover(); await snap.wait(0.6)
        engine.setNextFocus(minutes: 40)
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
        snap.note("launch: policy=\(policyName) mainVisible=\(windows.isMainVisible) page=\(mainState.page) loginItem=\(launchedAsLoginItemForCheck)")
        seedHistory()
        statsModel.reload()
        func tiles() -> String {
            StatsRange.allCases.map { "\($0)=\(TimeFormat.duration(statsModel.tiles[$0]?.focusSeconds ?? 0))/\(statsModel.tiles[$0]?.sessionCount ?? 0)" }
                .joined(separator: " ")
        }
        snap.note("tiles: \(tiles())")
        let view = { StatsView(model: self.statsModel, preferences: self.calendarPrefs).frame(width: 760, height: 560) }
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
        showStats()
        await snap.wait(0.5)
        if let content = windows.mainWindow?.contentView {
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
        snap.note("after close: policy=\(policyName) mainVisible=\(windows.isMainVisible) running=true")

        // Launching again from outside (as Spotlight does) brings the window back on the Timer page.
        mainState.page = .stats
        try? "ready".write(to: snap.directory.appendingPathComponent("ready-for-reopen"), atomically: true, encoding: .utf8)
        for _ in 0..<40 where !windows.isMainVisible { await snap.wait(0.25) }
        snap.note("after external launch: policy=\(policyName) mainVisible=\(windows.isMainVisible) page=\(mainState.page)")
        closeAllWindows()
        await snap.wait(0.5)

        // The popover's Stats button.
        statusItem.showPopover(fromClick: true)
        await snap.wait(0.3)
        showStats()
        await snap.wait(0.3)
        snap.note("popover Stats: popoverVisible=\(statusItem.popoverWindowVisible) mainVisible=\(windows.isMainVisible) page=\(mainState.page) policy=\(policyName)")

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

    func checkSettings(_ snap: DebugSnapshots) async {
        snap.note("== settings ==")
        let s = settings.settings
        snap.note("defaults: focus=\(s.focusMinutes) short=\(s.shortBreakMinutes) long=\(s.longBreakMinutes) " +
            "after=\(s.sessionsBeforeLongBreak) goal=\(TimeFormat.duration(s.dailyGoalSeconds)) sound=\(s.soundOn) " +
            "loginItemStatus=\(SMAppService.mainApp.status.rawValue) (0=notRegistered 1=enabled 2=requiresApproval 3=notFound)")

        // ⌘, through the real menu item.
        closeAllWindows()
        await snap.wait(0.4)
        let appMenu = NSApp.mainMenu?.item(withTitle: "FocusNow")?.submenu
        let settingsItem = appMenu?.item(withTitle: "Settings…")
        let quitItem = appMenu?.item(withTitle: "Quit FocusNow")
        snap.note("menu: Settings… key=\"\(settingsItem?.keyEquivalent ?? "-")\" Quit key=\"\(quitItem?.keyEquivalent ?? "-")\" " +
            "Window menu=\(NSApp.mainMenu?.item(withTitle: "Window")?.submenu?.items.map(\.title) ?? [])")
        if let item = settingsItem, let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
        await snap.wait(0.6)
        snap.note("after ⌘,: mainVisible=\(windows.isMainVisible) page=\(mainState.page) " +
            "section=\(mainState.settingsSection) policy=\(policyName)")

        engine.cancel()
        engine.skipBreak() // the stats phase may have left a break pending

        guard let window = windows.mainWindow, let frameView = window.contentView?.superview else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.4)
        func shot(_ name: String) async {
            await snap.wait(0.1)
            snap.capture(frameView, as: name, scale: 1)
        }
        func fields() -> Int { snap.textFields(in: window).count }
        func show(_ section: SettingsSection) async {
            await snap.selectRow(SettingsSection.allCases.firstIndex(of: section) ?? 0, in: window)
        }
        func focus() -> Int { settings.settings.focusMinutes }
        window.appearance = NSAppearance(named: .aqua)
        await shot("settings-cycle")
        window.appearance = NSAppearance(named: .darkAqua)
        await shot("settings-cycle-dark")
        window.appearance = nil
        for line in snap.spoken(roles: ["AXTextField", "AXIncrementor"], in: window) {
            snap.note("voiceover: \(line)")
        }

        // The Cycle pane edits the defaults for every session.
        await snap.type("30", intoField: 0, of: window)
        await snap.pressKey(36, characters: "\r", in: window)
        snap.note("focus field → settings=\(focus()) remaining=\(engine.remainingSeconds)")
        settings.settings.focusMinutes = 40
        await snap.type("6 sessions", intoField: 3, of: window)
        await snap.pressKey(36, characters: "\r", in: window)
        snap.note("after field → \(settings.settings.sessionsBeforeLongBreak) phase=\"\(engine.phaseLabel)\"")
        // A change made elsewhere (the stepper, the popover) while a field still
        // has focus must survive the field losing focus.
        settings.settings.sessionsBeforeLongBreak = 4
        await snap.wait(0.2)
        window.makeFirstResponder(nil)
        await snap.wait(0.3)
        snap.note("defaults kept after blur: focus=\(focus()) after=\(settings.settings.sessionsBeforeLongBreak)")
        // Focus changed and changed back before the next tick still drops a one-off.
        engine.setNextFocus(minutes: 50)
        settings.settings.focusMinutes = 30
        settings.settings.focusMinutes = 40
        snap.note("one-off after focus 30 and back: \(engine.nextFocusSecondsOverride.map(String.init) ?? "none") (want none)")

        // The stepper steps from what was typed, not from the value it replaces.
        await snap.type("25", intoField: 0, of: window)
        await snap.clickStepper(0, up: true, in: window)
        window.makeFirstResponder(nil)
        await snap.wait(0.3)
        snap.note("focus field 25 then stepper up → focus=\(focus()) (want 26)")
        settings.settings.focusMinutes = 40

        // During a session the lengths stay editable and apply from the next one.
        engine.start()
        await snap.wait(0.3)
        await snap.type("35", intoField: 0, of: window)
        await snap.pressKey(36, characters: "\r", in: window)
        snap.note("during a session: planned=\(engine.active?.plannedSeconds ?? -1) focus=\(focus()) (want 2400 35)")
        engine.cancel()
        await snap.wait(0.3)
        snap.note("idle after: remaining=\(engine.remainingSeconds) (want 2100)")
        settings.settings.focusMinutes = 40
        window.makeFirstResponder(nil)

        // The sidebar picks the pane.
        await show(.goal)
        snap.note("section=\(mainState.settingsSection) fields=\(fields()) (want goal 1)")
        await shot("settings-goal")

        // Typing the goal: Return commits, nonsense and Escape put the old value
        // back, and leaving the field commits.
        func goal() -> String { TimeFormat.duration(settings.settings.dailyGoalSeconds) }
        await snap.type("3h 30m", intoField: 0, of: window)
        await snap.pressKey(36, characters: "\r", in: window)
        snap.note("typed 3h 30m → \(goal())")
        let rejectedBefore = InputFeedback.rejections
        await snap.type("abc", intoField: 0, of: window)
        await snap.pressKey(36, characters: "\r", in: window)
        snap.note("typed abc → \(goal()) beeped=\(InputFeedback.rejections - rejectedBefore) (want 1)")
        await snap.type("", intoField: 0, of: window)
        await snap.pressKey(51, characters: "\u{7f}", in: window) // Delete
        await snap.pressKey(36, characters: "\r", in: window)
        snap.note("cleared → \(goal()) beeped=\(InputFeedback.rejections - rejectedBefore) (want 1)")
        await snap.type("5h", intoField: 0, of: window)
        await snap.pressKey(53, characters: "\u{1b}", in: window)
        snap.note("escape → \(goal())")
        await snap.type("2h", intoField: 0, of: window)
        window.makeFirstResponder(nil)
        await snap.wait(0.3)
        snap.note("left field → \(goal())")

        await show(.general)
        let toggles = snap.spoken(roles: ["AXCheckBox", "AXSwitch"], in: window)
        snap.note("section=\(mainState.settingsSection) toggles=\(toggles.count) (want general 2)")
        for line in toggles { snap.note("voiceover: \(line)") }
        await shot("settings-general")

        // Typed text not yet committed survives leaving the pane, the tab or the window.
        await show(.cycle)
        await snap.type("33", intoField: 0, of: window)
        await show(.general)
        snap.note("focus 33 then General → \(focus()) (want 33)")
        await show(.cycle)
        await snap.type("34", intoField: 0, of: window)
        let toTimer = await command("1", 18, in: window)
        snap.note("focus 34 then ⌘1 → \(focus()) handled=\(toTimer) page=\(mainState.page) (want 34 true timer)")
        showSettings()
        await snap.wait(0.5)
        await snap.type("36", intoField: 0, of: window)
        window.performClose(nil)
        await snap.wait(0.5)
        snap.note("focus 36 then close → \(focus()) mainVisible=\(windows.isMainVisible) (want 36 false)")
        settings.settings.focusMinutes = 40

        // The other ways in: ⌘3, and the popover's Settings button.
        showTimer()
        await snap.wait(0.5)
        let toSettings = await command("3", 20, in: window)
        snap.note("⌘3 handled=\(toSettings) page=\(mainState.page)")
        await show(.goal) // remembered while the app runs
        closeAllWindows()
        await snap.wait(0.4)
        mainState.page = .timer
        statusItem.showPopover(fromClick: true)
        await snap.wait(0.5)
        if let popover = statusItem.popoverWindow {
            _ = await snap.press(accessibilityLabel: "Settings", in: popover)
        }
        await snap.wait(0.6)
        snap.note("popover Settings: popoverVisible=\(statusItem.popoverWindowVisible) mainVisible=\(windows.isMainVisible) " +
            "page=\(mainState.page) section=\(mainState.settingsSection) policy=\(policyName) (want false true settings goal)")

        // The smallest window still shows every row of the Cycle pane.
        await show(.cycle)
        window.setContentSize(NSSize(width: 640, height: 480))
        await snap.wait(0.4)
        let content = window.contentView?.bounds ?? .zero
        let inside = snap.textFields(in: window).allSatisfy { content.contains($0.convert($0.bounds, to: nil)) }
        snap.note("min size: fields=\(fields()) all inside=\(inside) (want 4 true)")
        await shot("settings-cycle-min")
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.3)

        // A new goal applies from today and leaves past days alone.
        statsModel.range = .month
        let metBefore = statsModel.summary.goalMetDays
        settings.settings.dailyGoalSeconds = 3 * 3600
        await snap.wait(0.3)
        snap.note("goal → 3h: todayGoal=\(TimeFormat.duration(statsModel.todayGoalSeconds)) " +
            "month goal-met days before=\(metBefore) after=\(statsModel.summary.goalMetDays) history=\(settings.goalHistory.count)")
        statsModel.range = .week

        // Sound off silences the finish sound.
        settings.settings.soundOn = false
        snap.note("sound off: finish would play sound=\(alerter.sessionFinished(.focus))")
        await show(.general)
        await shot("settings-after-changes")

        closeAllWindows()
        await snap.wait(0.4)
        snap.note("after closing Settings: policy=\(policyName)")
    }

    func checkTimer(_ snap: DebugSnapshots) async {
        snap.note("== timer ==")
        engine.cancel()
        engine.skipBreak() // earlier phases may have left a break pending
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
        func fields() -> Int { snap.textFields(in: window).count }
        func shot(_ name: String) async {
            await snap.wait(0.1)
            snap.capture(frameView, as: name, scale: 1)
        }
        /// The digits' height: their font is sized from the ring, so it follows the ring's size.
        func ring() -> Int { Int(snap.accessibilityFrame(of: TimerRing.digitsIdentifier, in: window)?.height ?? -1) }
        snap.note("launch page=\(mainState.page) mainVisible=\(windows.isMainVisible) fields=\(fields()) (want 0) " +
            "toolbarItems=\(window.toolbar?.items.count ?? 0) policy=\(policyName)")
        snap.note("window place saved as \"\(window.frameAutosaveName)\" (want \"\" while testing)")
        // What VoiceOver reads: the digits read the time, then the controls.
        for line in snap.spoken(roles: ["AXButton", "AXTextField", "AXIncrementor"], in: window) {
            snap.note("voiceover: \(line)")
        }
        window.appearance = NSAppearance(named: .aqua)
        await shot("timer-idle")
        window.appearance = NSAppearance(named: .darkAqua)
        await shot("timer-idle-dark")
        window.appearance = nil

        // One layout: the ring keeps its size when a session starts.
        let idleRing = ring()
        engine.start()
        await snap.wait(0.6)
        snap.note("running fields=\(fields()) inSession=\(engine.isInSession) ring idle=\(idleRing) running=\(ring()) (want 0 true, equal)")
        await shot("timer-running")
        engine.pause()
        await snap.wait(0.4)
        snap.note("paused fields=\(fields())")
        await shot("timer-paused")
        engine.cancel()
        await snap.wait(0.6)
        snap.note("after cancel fields=\(fields())")
        await shot("timer-after-cancel")

        // ⌘2 and ⌘1 through the real menu.
        for (key, code) in [("2", UInt16(19)), ("1", UInt16(18))] {
            let handled = await command(key, code, in: window)
            snap.note("⌘\(key) handled=\(handled) page=\(mainState.page)")
            if key == "2" { await shot("stats-page") }
        }

        // Window extremes.
        window.setContentSize(NSSize(width: 640, height: 480))
        await snap.wait(0.5)
        let idleMinRing = ring()
        snap.note("min size fields=\(fields()) content=\(window.contentView?.bounds.size ?? .zero)")
        await shot("timer-idle-min")
        engine.start()
        await snap.wait(0.6)
        snap.note("min size ring idle=\(idleMinRing) running=\(ring()) (want equal)")
        await shot("timer-running-min")
        engine.cancel()
        window.setContentSize(NSSize(width: 1400, height: 900))
        await snap.wait(0.4)
        engine.setNextFocus(minutes: 180)
        engine.start()
        await snap.wait(0.6)
        snap.note("large content=\(window.contentView?.bounds.size ?? .zero) remaining=\(TimeFormat.clock(engine.remainingSeconds))")
        await shot("timer-running-large")
        engine.cancel()
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.4)
    }

    func checkDigits(_ snap: DebugSnapshots) async {
        snap.note("== digits ==")
        engine.cancel()
        engine.skipBreak()
        showTimer()
        await snap.wait(0.6)
        guard let window = windows.mainWindow else {
            snap.note("no main window")
            return
        }
        let label = TimerRing.digitsIdentifier
        func remaining() -> Int { engine.remainingSeconds }
        /// Clicks the digits and types; returns whether a field took the text.
        func edit(_ text: String, in window: NSWindow) async -> Bool {
            guard await snap.press(accessibilityLabel: label, in: window) else { return false }
            guard window.firstResponder is NSText else {
                snap.note("digits did not become a field")
                return false
            }
            await snap.typeIntoFocusedField(text, in: window)
            return true
        }
        let ret: (UInt16, String) = (36, "\r"), esc: (UInt16, String) = (53, "\u{1b}")

        // On the Timer page.
        if await edit("25", in: window) { await snap.pressKey(ret.0, characters: ret.1, in: window) }
        snap.note("digits 25 → remaining=\(remaining())")
        let rejectedBefore = InputFeedback.rejections
        if await edit("abc", in: window) { await snap.pressKey(ret.0, characters: ret.1, in: window) }
        snap.note("digits abc → \(remaining()) beeped=\(InputFeedback.rejections - rejectedBefore) (want 1)")
        if await edit("45:00", in: window) { await snap.pressKey(ret.0, characters: ret.1, in: window) }
        snap.note("digits 45:00 → \(remaining()) (want 2700)")
        if await edit("25:30", in: window) { await snap.pressKey(ret.0, characters: ret.1, in: window) }
        snap.note("digits 25:30 → \(remaining()) beeped=\(InputFeedback.rejections - rejectedBefore) (want 2)")
        if await edit("", in: window) {
            await snap.pressKey(51, characters: "\u{7f}", in: window) // Delete
            await snap.pressKey(ret.0, characters: ret.1, in: window)
        }
        snap.note("digits cleared → \(remaining()) beeped=\(InputFeedback.rejections - rejectedBefore) (want 2)")
        engine.setNextFocus(minutes: 25)
        if await edit("50", in: window) { await snap.pressKey(esc.0, characters: esc.1, in: window) }
        snap.note("digits escape → \(remaining())")

        // A session started elsewhere (the popover) while typing drops the edit.
        engine.setNextFocus(minutes: 40)
        _ = await edit("35", in: window)
        engine.start()
        await snap.wait(0.6)
        snap.note("start mid-edit → planned=\(engine.active?.plannedSeconds ?? -1) fields=\(snap.textFields(in: window).count)")
        engine.cancel()
        await snap.wait(0.6)

        // The longest length fits.
        if await edit("180", in: window) { await snap.pressKey(ret.0, characters: ret.1, in: window) }
        snap.note("digits 180 → \(TimeFormat.clock(remaining()))")
        if let frameView = window.contentView?.superview { snap.capture(frameView, as: "timer-idle-180", scale: 1) }
        snap.render(PopoverView(engine: engine, settings: settings, appearance: appearancePrefs), as: "popover-180")
        engine.setNextFocus(minutes: 40)

        // In the popover.
        closeAllWindows()
        await snap.wait(0.4)
        statusItem.showPopover(fromClick: true)
        await snap.wait(0.5)
        guard let popover = statusItem.popoverWindow else {
            snap.note("no popover window")
            return
        }
        if await edit("35", in: popover) {
            snap.note("popover editing active=\(NSApp.isActive) key=\(popover.isKeyWindow)")
            await snap.pressKey(ret.0, characters: ret.1, in: popover)
        }
        snap.note("popover digits 35 → \(remaining())")
        _ = await edit("20", in: popover)
        statusItem.closePopover()
        await snap.wait(0.5)
        snap.note("popover closed mid-edit → \(remaining())")
        engine.setNextFocus(minutes: 40)
        await snap.wait(1.0) // the popover reports itself shown for a moment after closing
    }

    /// What happens to half-typed values when something else is clicked, and
    /// to the finish popover when the owner answers in the window.
    func checkCommits(_ snap: DebugSnapshots) async {
        snap.note("== commits ==")
        engine.cancel()
        engine.skipBreak()
        engine.setNextFocus(minutes: 40)
        showTimer()
        await snap.wait(0.6)
        guard let window = windows.mainWindow else {
            snap.note("no main window")
            return
        }
        func planned() -> Int { engine.active?.plannedSeconds ?? -1 }
        func typeDigits(_ text: String) async {
            guard await snap.press(accessibilityLabel: TimerRing.digitsIdentifier, in: window),
                  window.firstResponder is NSText else {
                snap.note("digits did not become a field")
                return
            }
            await snap.typeIntoFocusedField(text, in: window)
        }
        func reset() async {
            engine.cancel()
            settings.settings.focusMinutes = 40
            engine.setNextFocus(minutes: 40)
            window.makeFirstResponder(nil)
            await snap.wait(0.6)
        }

        // Typing, then clicking a control on the same page: what was typed applies first.
        await typeDigits("25")
        _ = await snap.press(accessibilityLabel: "Start focus", in: window)
        snap.note("digits 25 then Start → planned=\(planned())")
        await reset()
        await typeDigits("25")
        _ = await snap.press(accessibilityLabel: "Five minutes longer", in: window)
        snap.note("digits 25 then + → remaining=\(engine.remainingSeconds)")
        await reset()

        // Leaving the Timer page mid-edit keeps what was typed, as closing does.
        await typeDigits("25")
        _ = await command(",", 43, in: window)
        _ = await command("1", 18, in: window)
        snap.note("digits 25 then ⌘, then ⌘1 → remaining=\(engine.remainingSeconds) page=\(mainState.page) (want 1500 timer)")
        await reset()

        // A finish opens the popover; answering in the window closes it.
        engine.nextFocusSecondsOverride = 2
        engine.start()
        await snap.wait(3.0)
        snap.note("finished: popoverVisible=\(statusItem.popoverWindowVisible) closesOnOutsideClick=\(statusItem.closesOnOutsideClick)")
        _ = await snap.press(accessibilityLabel: "Start break", in: window)
        await snap.wait(0.6)
        snap.note("Start break in window → popoverVisible=\(statusItem.popoverWindowVisible) status=\(engine.status) phase=\"\(engine.phaseLabel)\"")
        engine.skipBreak()
        await snap.wait(1.0)
    }

    /// A ⌘-key shortcut through the real menu; returns whether the menu took it.
    private func command(_ key: String, _ code: UInt16, in window: NSWindow) async -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)
        else { return false }
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
        try? await Task.sleep(for: .seconds(0.4))
        return handled
    }

    func closeAllWindows() {
        for window in NSApp.windows where window.isVisible && window.title.isEmpty == false {
            window.performClose(nil)
        }
    }

    /// About six weeks of plausible history, so the stats window has something to show.
    func seedHistory() {
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
        let popover = { PopoverView(engine: self.engine, settings: self.settings, appearance: self.appearancePrefs) }
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
        snap.note("click 1: popoverVisible=\(statusItem.popoverWindowVisible) closesOnOutsideClick=\(statusItem.closesOnOutsideClick) active=\(NSApp.isActive)")
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
        snap.note("finished popover closesOnOutsideClick=\(statusItem.closesOnOutsideClick) " +
            "frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
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
