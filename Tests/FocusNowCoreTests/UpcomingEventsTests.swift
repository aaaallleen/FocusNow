import Foundation
import Testing
@testable import FocusNowCore

struct UpcomingEventsTests {
    let now = date("2026-11-19T10:15:00Z")
    let events = [
        event("overnight", "2026-11-18T22:00:00Z", "2026-11-19T11:00:00Z"),
        event("standup", "2026-11-19T10:00:00Z", "2026-11-19T10:30:00Z"),
        event("review", "2026-11-19T11:00:00Z", "2026-11-19T12:00:00Z"),
        event("oneonone", "2026-11-19T14:00:00Z", "2026-11-19T14:30:00Z"),
        event("retro", "2026-11-19T15:00:00Z", "2026-11-19T16:00:00Z"),
        event("late", "2026-11-19T17:00:00Z", "2026-11-19T18:00:00Z"),
        event("ended", "2026-11-19T08:00:00Z", "2026-11-19T09:00:00Z"),
        event("holiday", "2026-11-19T00:00:00Z", "2026-11-20T00:00:00Z", allDay: true),
        event("declined", "2026-11-19T13:00:00Z", "2026-11-19T13:30:00Z", declined: true),
        event("cancelled", "2026-11-19T13:30:00Z", "2026-11-19T14:00:00Z", cancelled: true),
        event("tomorrow", "2026-11-20T09:00:00Z", "2026-11-20T10:00:00Z"),
        event("hidden", "2026-11-19T12:30:00Z", "2026-11-19T13:00:00Z", calendar: "home"),
    ]

    @Test func listsTodaysRemainingTimedEventsInOrder() {
        let list = UpcomingEvents.list(events, hidden: ["home"], now: now, calendar: utc, limit: 10)
        #expect(list.rows.map(\.event.id) == ["overnight", "standup", "review", "oneonone", "retro", "late"])
        #expect(list.rows.map(\.isNow) == [true, true, false, false, false, false])
        #expect(list.moreCount == 0)
    }

    @Test func overnightEventInProgressIsNow() {
        let list = UpcomingEvents.list([events[0]], hidden: [], now: now, calendar: utc)
        #expect(list.rows.map(\.event.id) == ["overnight"])
        #expect(list.rows.first?.isNow == true)
    }

    @Test func hiddenCalendarsOnlyHideTheirOwn() {
        let list = UpcomingEvents.list(events, hidden: [], now: now, calendar: utc, limit: 10)
        #expect(list.rows.map(\.event.id).contains("hidden"))
        #expect(list.rows.count == 7)
    }

    @Test func capsAtThreeAndCountsTheRest() {
        let list = UpcomingEvents.list(events, hidden: ["home"], now: now, calendar: utc)
        #expect(list.rows.count == 3)
        #expect(list.moreCount == 3)
        #expect(list.trimmed(to: 1) == UpcomingList(rows: [list.rows[0]], moreCount: 5))
        #expect(list.trimmed(to: 5) == list)
    }

    @Test func sameStartOrdersByTitle() {
        let pair = [
            event("b", "2026-11-19T11:00:00Z", "2026-11-19T11:30:00Z", title: "B"),
            event("a", "2026-11-19T11:00:00Z", "2026-11-19T11:30:00Z", title: "A"),
        ]
        #expect(UpcomingEvents.list(pair, hidden: [], now: now, calendar: utc).rows.map(\.event.title) == ["A", "B"])
    }

    @Test func endingNowIsGoneAndStartingNowIsNow() {
        let edge = [
            event("ending", "2026-11-19T09:45:00Z", "2026-11-19T10:15:00Z"),
            event("starting", "2026-11-19T10:15:00Z", "2026-11-19T10:45:00Z"),
        ]
        let list = UpcomingEvents.list(edge, hidden: [], now: now, calendar: utc)
        #expect(list.rows.map(\.event.id) == ["starting"])
        #expect(list.rows.first?.isNow == true)
    }

    @Test func nextChangeIsTheNextStartOrEndOrMidnight() {
        #expect(UpcomingEvents.nextChange(events, hidden: ["home"], now: now, calendar: utc) == date("2026-11-19T10:30:00Z"))
        #expect(UpcomingEvents.nextChange([], hidden: [], now: now, calendar: utc) == date("2026-11-20T00:00:00Z"))
    }
}
