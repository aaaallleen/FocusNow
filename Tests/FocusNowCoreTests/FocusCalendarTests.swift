import Foundation
import Testing
@testable import FocusNowCore

/// A focus session whose end time differs from start + focused time (it was paused).
func session(start: String, active: Int, endedAt: String) -> SessionRecord {
    SessionRecord(kind: .focus, startedAt: date(start), endedAt: date(endedAt),
                  plannedSeconds: 2400, activeSeconds: active, outcome: .endedEarly)
}

struct FocusCalendarTests {
    let cal = FocusCalendar(calendar: utc)

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    @Test func blockRunsForTheFocusedTime() {
        let blocks = cal.blocks([session(start: "2026-11-19T17:30:00Z", active: 1200, endedAt: "2026-11-20T08:00:00Z")])
        #expect(blocks.count == 1)
        #expect(blocks[0].start == date("2026-11-19T17:30:00Z"))
        #expect(blocks[0].end == date("2026-11-19T17:50:00Z"))
        #expect(near(blocks[0].startHour, 17.5))
        #expect(near(blocks[0].endHour, 17 + 50.0 / 60))
    }

    @Test func blocksClipAtMidnight() {
        let block = cal.blocks([focus("2026-11-19T23:30:00Z", 3600)])[0]
        #expect(block.end == date("2026-11-20T00:00:00Z"))
        #expect(block.endHour == 24)
    }

    @Test func breaksAreNotBlocks() {
        #expect(cal.blocks([rest("2026-11-19T09:40:00Z", 300)]).isEmpty)
    }

    @Test func periodsJoinGapsUnder15Minutes() {
        let blocks = cal.blocks([
            focus("2026-11-19T10:00:00Z", 2400), focus("2026-11-19T10:45:00Z", 2400), focus("2026-11-19T11:40:00Z", 2400),
        ])
        #expect(cal.periods(blocks) == [
            FocusPeriod(start: date("2026-11-19T10:00:00Z"), end: date("2026-11-19T11:25:00Z")),
            FocusPeriod(start: date("2026-11-19T11:40:00Z"), end: date("2026-11-19T12:20:00Z")),
        ])
    }

    @Test func hourSpanPadsAnHourAndKeepsSix() {
        func span(_ sessions: [SessionRecord]) -> HourSpan? { cal.hourSpan(cal.blocks(sessions)) }
        #expect(span([focus("2026-11-19T10:00:00Z", 2400)]) == HourSpan(first: 9, last: 15))
        #expect(span([focus("2026-11-19T08:10:00Z", 1800), focus("2026-11-19T16:50:00Z", 1800)]) == HourSpan(first: 7, last: 19))
        #expect(span([focus("2026-11-19T00:20:00Z", 2400)]) == HourSpan(first: 0, last: 6))
        #expect(span([focus("2026-11-19T22:00:00Z", 3600)]) == HourSpan(first: 18, last: 24))
        #expect(span([focus("2026-11-19T23:30:00Z", 3600)]) == HourSpan(first: 18, last: 24))
    }

    @Test func emptyHasNoSpan() {
        #expect(cal.hourSpan([]) == nil)
    }

    @Test func clockChangeDayUsesWallClock() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-03-08 is the spring-forward day: 10:00 local is 14:00Z.
        let block = FocusCalendar(calendar: ny).blocks([focus("2026-03-08T14:00:00Z", 2400)])[0]
        #expect(near(block.startHour, 10))
        #expect(near(block.endHour, 10 + 40.0 / 60))
    }

    @Test func daysTotalAndSplitPerDay() {
        let sessions = [
            focus("2026-11-16T09:00:00Z", 7200),
            focus("2026-11-17T09:00:00Z", 3600), focus("2026-11-17T14:00:00Z", 3600),
            focus("2026-11-18T09:00:00Z", 5000),
            focus("2026-11-19T09:00:00Z", 2400), focus("2026-11-19T10:00:00Z", 1500),
            rest("2026-11-19T09:40:00Z", 300),
        ]
        let week = DateInterval(start: date("2026-11-16T00:00:00Z"), end: date("2026-11-23T00:00:00Z"))
        let days = cal.days(in: week, sessions: sessions)
        #expect(days.count == 7)
        #expect(days.map(\.focusSeconds) == [7200, 7200, 5000, 3900, 0, 0, 0])
        #expect(days[1].blocks.count == 2)
        #expect(days[3].periods.count == 2)
        #expect(days[0].day.start == date("2026-11-16T00:00:00Z"))
    }

    @Test func monthWeeksFollowTheFirstWeekday() {
        func month(_ start: String, _ end: String) -> DateInterval { DateInterval(start: date(start), end: date(end)) }
        let nov = month("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z")
        let weeks = cal.monthWeeks(nov)
        #expect(weeks.count == 6)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0] == [nil, nil, nil, nil, nil, nil, date("2026-11-01T00:00:00Z")])
        #expect(weeks[5] == [date("2026-11-30T00:00:00Z"), nil, nil, nil, nil, nil, nil])
        #expect(cal.monthWeeks(month("2026-12-01T00:00:00Z", "2027-01-01T00:00:00Z")).count == 5)
        #expect(cal.monthWeeks(month("2027-02-01T00:00:00Z", "2027-03-01T00:00:00Z")).count == 4)
        var sundayFirst = utc
        sundayFirst.firstWeekday = 1
        let sunday = FocusCalendar(calendar: sundayFirst).monthWeeks(nov)
        #expect(sunday.count == 5)
        #expect(sunday[0][0] == date("2026-11-01T00:00:00Z"))
    }
}

struct PeriodFormatTests {
    func text(_ start: String, _ end: String, _ uses24Hour: Bool = false) -> String {
        PeriodFormat.text(FocusPeriod(start: date("2026-11-19T\(start):00Z"), end: date(end == "24:00" ? "2026-11-20T00:00:00Z" : "2026-11-19T\(end):00Z")),
                          calendar: utc, uses24Hour: uses24Hour)
    }

    @Test func twelveHour() {
        #expect(text("10:00", "11:50") == "10–11:50 am")
        #expect(text("11:30", "13:00") == "11:30 am–1 pm")
        #expect(text("16:00", "19:00") == "4–7 pm")
        #expect(text("10:00", "12:00") == "10 am–12 pm")
        #expect(text("23:00", "24:00") == "11 pm–12 am")
        #expect(text("00:30", "01:00") == "12:30–1 am")
    }

    @Test func twentyFourHour() {
        #expect(text("10:00", "11:50", true) == "10:00–11:50")
        #expect(text("16:00", "19:00", true) == "16:00–19:00")
        #expect(text("23:00", "24:00", true) == "23:00–24:00")
    }
}
