import AppKit
import FocusNowCore
import SwiftUI

/// The calendar self-check. It runs on FakeCalendarSource only: it never reads
/// the owner's calendar and never shows the system permission prompt.
extension AppDelegate {
    func checkCalendar(_ snap: DebugSnapshots) async {
        snap.note("== calendar ==")
        guard let fake = calendarSource as? FakeCalendarSource else {
            snap.note("calendar source=real: stopping (the self-check only runs on the fake)")
            return
        }
        seedCalendar(fake)
        calendarModel.refresh()

        closeAllWindows()
        await snap.wait(0.4)
        showCalendarSettings()
        await snap.wait(0.6)
        guard let window = windows.mainWindow, let frameView = window.contentView?.superview else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.4)
        func present(_ label: String) -> Bool { snap.accessibilityFrame(of: label, in: window) != nil }
        func shot(_ name: String) async {
            await snap.wait(0.2)
            snap.capture(frameView, as: name, scale: 1)
        }
        func toggles() -> Int { ["Work", "Home", "Birthdays"].filter(present).count }
        func shows(_ text: String) -> Bool { snap.containsText(text, in: window) }

        snap.note("calendar source=fake page=\(mainState.page) section=\(mainState.settingsSection) " +
            "access=\(calendarModel.access) allow=\(present("Allow Access…")) requests=\(fake.requestCount) " +
            "(want settings calendar notAsked true 0)")
        await shot("settings-calendar-not-asked")
        _ = await snap.press(accessibilityLabel: "Allow Access…", in: window)
        await snap.wait(0.4)
        snap.note("after Allow: access=\(calendarModel.access) requests=\(fake.requestCount) " +
            "groups=\(calendarModel.groups.count) toggles=\(toggles()) (want granted 1 2 3)")
        window.appearance = NSAppearance(named: .aqua)
        await shot("settings-calendar")
        window.appearance = NSAppearance(named: .darkAqua)
        await shot("settings-calendar-dark")
        window.appearance = nil
        for line in snap.spoken(roles: ["AXButton", "AXCheckBox"], in: window) {
            snap.note("voiceover: \(line)")
        }

        // A real click in the middle of the row: between the dot and the name.
        _ = await snap.press(accessibilityLabel: "Work", in: window)
        await snap.wait(0.2)
        snap.note("untick Work: hidden=\(calendarPrefs.hiddenCalendarIDs.sorted()) (want [\"work\"])")

        fake.access = .denied
        fake.simulateChange()
        await snap.wait(0.3)
        snap.note("denied: privacy=\(present("Open Privacy & Security")) off=\(shows("Calendar access is off.")) " +
            "groups=\(calendarModel.groups.count) toggles=\(toggles()) (want true true 0 0)")
        await shot("settings-calendar-denied")
        fake.access = .writeOnly
        fake.simulateChange()
        await snap.wait(0.3)
        snap.note("writeOnly: privacy=\(present("Open Privacy & Security")) groups=\(calendarModel.groups.count) (want true 0)")

        // Left granted with every calendar ticked for the Timer page checks.
        fake.access = .granted
        calendarModel.setShown(true, calendarID: "work")
        fake.simulateChange()
        await snap.wait(0.3)
        snap.note("restored: access=\(calendarModel.access) hidden=\(calendarPrefs.hiddenCalendarIDs.sorted()) " +
            "upcoming=\(calendarModel.upcoming.rows.count)+\(calendarModel.upcoming.moreCount)")

        await checkTimerEvents(snap, fake: fake)
        await checkStatsCalendar(snap)
    }

    /// Stats' Chart | Calendar switch and the calendar views.
    private func checkStatsCalendar(_ snap: DebugSnapshots) async {
        if sessions.earliestStart() == nil { seedHistory() }
        // A busy day in last month (always fully past): six 20-minute sessions an hour apart.
        let calendar = Calendar.autoupdatingCurrent
        let thisMonth = calendar.dateInterval(of: .month, for: Date())!.start
        let busyDay = calendar.date(byAdding: DateComponents(month: -1, day: 14), to: thisMonth)!
        for hour in 18...23 {
            let start = calendar.date(byAdding: .hour, value: hour, to: busyDay)!
            sessions.save(SessionRecord(kind: .focus, startedAt: start, endedAt: start.addingTimeInterval(1200),
                                        plannedSeconds: 1200, activeSeconds: 1200, outcome: .completed))
        }
        statsModel.reload()

        closeAllWindows()
        await snap.wait(0.4)
        showStats()
        await snap.wait(0.6)
        guard let window = windows.mainWindow else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.4)
        func present(_ label: String) -> Bool { snap.accessibilityFrame(of: label, in: window) != nil }
        func shows(_ text: String) -> Bool { snap.containsText(text, in: window) }
        func listShown() -> Bool { snap.readable(in: window).contains { $0.text.hasPrefix("Sessions · ") } }
        let view = { StatsView(model: self.statsModel, preferences: self.calendarPrefs) }

        var offered: [String] = []
        for range in StatsRange.allCases {
            statsModel.range = range
            await snap.wait(0.3)
            offered.append("\(range)=\(present(StatsView.displaySwitchIdentifier))")
        }
        snap.note("stats switch: \(offered.joined(separator: " ")) (want day week month true, year allTime false)")

        calendarPrefs.statsDisplay = .calendar
        statsModel.range = .week
        await snap.wait(0.4)
        let blocks = statsModel.focusDays.reduce(0) { $0 + $1.blocks.count }
        let span = statsModel.hourSpan.map { "\($0.first)–\($0.last)" } ?? "none"
        snap.note("calendar week: days=\(statsModel.focusDays.count) blocks=\(blocks) span=\(span) " +
            "sessionList=\(listShown()) (want 7 >0 a span false)")
        snap.render(view().frame(width: 760, height: 560), as: "stats-calendar-week")
        // The live window too: the off-screen renderer can't draw the AppKit switch.
        if let frameView = window.contentView?.superview { snap.capture(frameView, as: "stats-calendar-week-live", scale: 1) }
        snap.render(view().frame(width: 760, height: 560), as: "stats-calendar-week-dark", dark: true)
        statsModel.range = .day
        snap.render(view().frame(width: 760, height: 560), as: "stats-calendar-day")

        statsModel.range = .month
        statsModel.pageBack()
        await snap.wait(0.4)
        let busy = statsModel.focusDays.first { $0.day.start == busyDay }
        let busyLabel = snap.readable(in: window).first { $0.text.hasPrefix(busyDay.formatted(.dateTime.month(.abbreviated).day()) + ",") }?.text
        snap.note("calendar month: weeks=\(statsModel.monthWeeks.count) busy periods=\(busy?.periods.count ?? -1) " +
            "label=\"\(busyLabel ?? "-")\" (want 4–6 ≥6 the date, total and every period)")
        snap.render(view().frame(width: 760, height: 560), as: "stats-calendar-month")
        snap.render(view().frame(width: 640, height: 480), as: "stats-calendar-month-min")

        statsModel.range = .day
        for _ in 0..<14 where !(statsModel.focusDays.first?.blocks.isEmpty ?? true) { statsModel.pageBack() }
        await snap.wait(0.4)
        snap.note("empty day: blocks=\(statsModel.focusDays.first?.blocks.count ?? -1) " +
            "text=\(shows("No focus sessions")) (want 0 true)")

        calendarPrefs.statsDisplay = .chart
        await snap.wait(0.4)
        snap.note("chart again: sessionList=\(listShown()) (want true)")
        statsModel.range = .week
        closeAllWindows()
        await snap.wait(0.3)
    }

    /// Today's events under the timer.
    private func checkTimerEvents(_ snap: DebugSnapshots, fake: FakeCalendarSource) async {
        showTimer()
        await snap.wait(0.6)
        guard let window = windows.mainWindow, let frameView = window.contentView?.superview else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.5)
        func shot(_ name: String) async {
            await snap.wait(0.2)
            snap.capture(frameView, as: name, scale: 1)
        }
        func rows() -> [(text: String, identifier: String?, frame: NSRect)] {
            snap.readable(in: window).filter { $0.identifier == UpcomingEventsView.rowIdentifier }
        }
        func shows(_ text: String) -> Bool { snap.containsText(text, in: window) }
        func ring() -> CGFloat { snap.accessibilityFrame(of: TimerRing.digitsIdentifier, in: window)?.height ?? -1 }
        let more = calendarModel.upcoming.moreCount

        snap.note("timer events: rows=\(rows().count) first=\"\(rows().first?.text ?? "-")\" " +
            "more=\(more) shown=\(shows("+\(more) more")) (want 3 \"… to …, Standup, now\" >0 true)")
        window.appearance = NSAppearance(named: .aqua)
        await shot("timer-events")
        window.appearance = NSAppearance(named: .darkAqua)
        await shot("timer-events-dark")
        window.appearance = nil
        for row in rows() { snap.note("voiceover row: \(row.text)") }

        let heights = rows().map { Int($0.frame.height) }
        snap.note("long title row heights=\(heights) (want all equal)")

        calendarModel.setShown(false, calendarID: "work")
        await snap.wait(0.3)
        let workTitles = ["Standup", "Design review", "1:1"]
        snap.note("hidden Work: rows=\(rows().map(\.text)) exclude work=" +
            "\(!rows().contains { row in workTitles.contains { row.text.contains(", \($0),") } }) (want true)")
        calendarModel.setShown(true, calendarID: "work")
        await snap.wait(0.3)

        let ringWith = ring()
        calendarPrefs.showOnTimerPage = false
        await snap.wait(0.4)
        snap.note("switch off: rows=\(rows().count) link=\(shows("Show your calendar here")) " +
            "ringBigger=\(ring() > ringWith) (\(Int(ringWith))→\(Int(ring()))) (want 0 false true)")
        calendarPrefs.showOnTimerPage = true
        await snap.wait(0.3)

        let seeded = fake.eventList
        fake.eventList = seeded.map { event in
            var past = event
            past.start = Date().addingTimeInterval(-7200)
            past.end = Date().addingTimeInterval(-3600)
            return past
        }
        fake.simulateChange()
        await snap.wait(0.3)
        snap.note("nothing left: rows=\(rows().count) text=\(shows("Nothing else on your calendar today")) (want 0 true)")
        fake.eventList = seeded

        fake.access = .notAsked
        fake.simulateChange()
        await snap.wait(0.3)
        let link = shows("Show your calendar here")
        _ = await snap.press(accessibilityLabel: "Show your calendar here", in: window)
        await snap.wait(0.4)
        snap.note("not granted: link=\(link) → page=\(mainState.page) section=\(mainState.settingsSection) " +
            "(want true settings calendar)")
        fake.access = .granted
        fake.simulateChange()

        // The smallest window: rows that fit, a ring of at least 120 pt, nothing overlapping.
        showTimer()
        await snap.wait(0.4)
        window.setContentSize(NSSize(width: 640, height: 480))
        await snap.wait(0.5)
        let size = window.contentView?.bounds.size ?? .zero
        let limit = TimerPageLayout.rows(for: size)
        let diameter = TimerPageLayout.diameter(
            for: size, eventsHeight: UpcomingEventsView.height(model: calendarModel, rowLimit: limit))
        let today = snap.readable(in: window).first { $0.text.hasPrefix("Today ") }?.frame ?? .zero
        let lowest = rows().map(\.frame).min { $0.minY < $1.minY } ?? .zero
        let moreLine = snap.readable(in: window).first { $0.text.hasSuffix(" more") }?.frame
        let bottom = min(lowest.minY, moreLine?.minY ?? .infinity)
        snap.note("min size \(Int(size.width))×\(Int(size.height)): rows=\(rows().count) limit=\(limit) " +
            "diameter=\(Int(diameter)) (want ≥1 ≥120) todayAboveEvents=\(today.minY >= (rows().map(\.frame.maxY).max() ?? 0) - 0.5) " +
            "eventsInside=\(bottom >= window.frame.minY) (want true true)")
        await shot("timer-events-min")
        window.setContentSize(NSSize(width: 760, height: 560))
    }

    /// Three calendars in two accounts; an event under way and four more spread
    /// between now and midnight, so the check works at any hour. One title is very long.
    func seedCalendar(_ fake: FakeCalendarSource) {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let blue = CalendarColor(red: 0.20, green: 0.47, blue: 0.96)
        let green = CalendarColor(red: 0.20, green: 0.70, blue: 0.35)
        let purple = CalendarColor(red: 0.60, green: 0.35, blue: 0.85)
        fake.calendarList = [
            CalendarInfo(id: "work", title: "Work", account: "Google", color: blue),
            CalendarInfo(id: "home", title: "Home", account: "iCloud", color: green),
            CalendarInfo(id: "birthdays", title: "Birthdays", account: "iCloud", color: purple),
        ]
        func event(_ id: String, _ title: String, _ calendarID: String, _ color: CalendarColor,
                   _ start: Date, _ end: Date) -> CalendarEvent {
            CalendarEvent(id: id, calendarID: calendarID, title: title, start: start, end: end,
                          isAllDay: false, isDeclined: false, isCancelled: false, color: color)
        }
        let step = midnight.timeIntervalSince(now) / 5
        func later(_ k: Double) -> Date { now.addingTimeInterval(step * k) }
        let longTitle = "Quarterly planning review with the whole product, design and engineering group, " +
            "including the roadmap walkthrough"
        fake.eventList = [
            event("standup", "Standup", "work", blue, now.addingTimeInterval(-600), now.addingTimeInterval(1200)),
            event("review", "Design review", "work", blue, later(1), later(1.5)),
            event("long", longTitle, "home", green, later(2), later(2.5)),
            event("oneonone", "1:1", "work", blue, later(3), later(3.5)),
            event("gym", "Gym", "home", green, later(4), later(4.5)),
        ]
    }
}
