import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct CalendarModelTests {
    let clock = FakeClock(date("2026-11-19T10:15:00Z"))
    let prefs = CalendarPreferences(defaults: freshDefaults())
    let fake: FakeCalendarSource

    init() {
        let gray = CalendarColor(red: 0.5, green: 0.5, blue: 0.5)
        fake = FakeCalendarSource(
            calendars: [
                CalendarInfo(id: "work", title: "Work", account: "Google", color: gray),
                CalendarInfo(id: "home", title: "Home", account: "iCloud", color: gray),
                CalendarInfo(id: "birthdays", title: "Birthdays", account: "iCloud", color: gray),
            ],
            events: [
                event("standup", "2026-11-19T10:00:00Z", "2026-11-19T10:30:00Z"),
                event("review", "2026-11-19T11:00:00Z", "2026-11-19T12:00:00Z"),
                event("gym", "2026-11-19T18:00:00Z", "2026-11-19T19:00:00Z", calendar: "home"),
            ])
    }

    func makeModel() -> CalendarModel {
        let clock = self.clock
        return CalendarModel(source: fake, preferences: prefs, clock: { clock.now }, calendar: utc)
    }

    func ids(_ model: CalendarModel) -> [String] { model.upcoming.rows.map(\.event.id) }

    @Test func notAskedShowsNothingAndNeverAsks() {
        let model = makeModel()
        model.refresh()
        #expect(model.access == .notAsked)
        #expect(model.groups.isEmpty)
        #expect(model.upcoming == .empty)
        #expect(fake.requestCount == 0)
    }

    @Test func grantingLoadsCalendarsGroupedByAccount() async {
        let model = makeModel()
        await model.requestAccess()
        #expect(model.access == .granted)
        #expect(model.groups.map(\.account) == ["Google", "iCloud"])
        #expect(model.groups[1].calendars.map(\.title) == ["Birthdays", "Home"])
        #expect(ids(model) == ["standup", "review", "gym"])
    }

    @Test func refusingLeavesItOff() async {
        fake.grantsOnRequest = false
        let model = makeModel()
        await model.requestAccess()
        #expect(model.access == .denied)
        #expect(model.groups.isEmpty)
    }

    @Test func aCalendarChangeRefreshes() {
        fake.access = .granted
        let model = makeModel()
        fake.eventList.append(event("new", "2026-11-19T13:00:00Z", "2026-11-19T13:30:00Z"))
        fake.simulateChange()
        #expect(ids(model) == ["standup", "review", "new"])
    }

    @Test func refreshIfDueDropsAnEndedEvent() {
        fake.access = .granted
        let model = makeModel()
        fake.eventList.removeAll { $0.id == "review" }
        clock.now = date("2026-11-19T10:16:00Z")
        model.refreshIfDue()
        #expect(ids(model).contains("review"))
        clock.now = date("2026-11-19T10:31:00Z")
        model.refreshIfDue()
        #expect(ids(model) == ["gym"])
    }

    @Test func hidingACalendarPersistsAndFilters() {
        fake.access = .granted
        let model = makeModel()
        model.setShown(false, calendarID: "work")
        #expect(prefs.hiddenCalendarIDs == ["work"])
        #expect(!model.isShown("work"))
        #expect(model.isShown("home"))
        #expect(ids(model) == ["gym"])
        model.setShown(true, calendarID: "work")
        #expect(prefs.hiddenCalendarIDs == [])
        #expect(ids(model) == ["standup", "review", "gym"])
    }

    @Test func newCalendarStartsShown() {
        fake.access = .granted
        let model = makeModel()
        model.setShown(false, calendarID: "work")
        fake.calendarList.append(CalendarInfo(
            id: "new", title: "New", account: "iCloud", color: CalendarColor(red: 1, green: 0, blue: 0)))
        fake.eventList.append(event("party", "2026-11-19T20:00:00Z", "2026-11-19T21:00:00Z", calendar: "new"))
        fake.simulateChange()
        #expect(model.isShown("new"))
        #expect(ids(model) == ["gym", "party"])
        fake.calendarList.removeAll { $0.id == "work" }
        fake.eventList.removeAll { $0.calendarID == "work" }
        fake.simulateChange()
        #expect(!model.groups.flatMap(\.calendars).map(\.id).contains("work"))
        #expect(ids(model) == ["gym", "party"])
    }

    @Test func revokedAccessClearsEverything() {
        fake.access = .granted
        let model = makeModel()
        #expect(!model.groups.isEmpty)
        fake.access = .denied
        fake.simulateChange()
        #expect(model.access == .denied)
        #expect(model.groups.isEmpty)
        #expect(model.upcoming == .empty)
    }

    @Test func writeOnlyCannotRead() {
        fake.access = .writeOnly
        let model = makeModel()
        #expect(model.access == .writeOnly)
        #expect(!model.access.canRead)
        #expect(model.upcoming == .empty)
    }

    @Test func aNewDayRefreshes() {
        fake.access = .granted
        let model = makeModel()
        fake.eventList.append(event("tomorrow", "2026-11-20T09:00:00Z", "2026-11-20T10:00:00Z"))
        clock.now = date("2026-11-20T08:00:00Z")
        model.refreshIfDue()
        #expect(ids(model) == ["tomorrow"])
    }
}
