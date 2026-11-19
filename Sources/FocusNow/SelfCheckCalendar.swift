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
