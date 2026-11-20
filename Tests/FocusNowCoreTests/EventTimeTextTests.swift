import Foundation
import Testing
@testable import FocusNowCore

/// The system's formats use narrow and thin no-break spaces ("1:30\u{202F}PM",
/// "1:30\u{2009}–\u{2009}3:47"); the app keeps them, the tests compare plain spaces.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
}

struct EventTimeTextTests {
    let us = Locale(identifier: "en_US")
    let gb = Locale(identifier: "en_GB")

    @Test func afternoonRangeSharesPM() {
        let t = plain(EventTimeText.range(event("e", "2026-11-19T13:30:00Z", "2026-11-19T15:47:00Z"), calendar: utc, locale: us))
        #expect(t.contains("1:30"))
        #expect(t.contains("3:47 PM"))
        #expect(t.components(separatedBy: "PM").count == 2, "\(t)")
    }

    @Test func rangeAcrossNoon() {
        let t = plain(EventTimeText.range(event("e", "2026-11-19T11:30:00Z", "2026-11-19T12:15:00Z"), calendar: utc, locale: us))
        #expect(t.contains("11:30 AM"), "\(t)")
        #expect(t.contains("12:15 PM"), "\(t)")
    }

    @Test func twentyFourHour() {
        let t = plain(EventTimeText.range(event("e", "2026-11-19T13:30:00Z", "2026-11-19T15:47:00Z"), calendar: utc, locale: gb))
        #expect(t.contains("13:30"), "\(t)")
        #expect(t.contains("15:47"), "\(t)")
    }

    @Test func overnightShowsTimesOnly() {
        let t = plain(EventTimeText.range(event("e", "2026-11-18T23:00:00Z", "2026-11-19T01:00:00Z"), calendar: utc, locale: us))
        #expect(t.contains("11:00 PM"), "\(t)")
        #expect(t.contains("1:00 AM"), "\(t)")
        #expect(!t.contains("Nov"), "\(t)")
        #expect(!t.contains("18"), "\(t)")
    }

    /// Locales that write dates as numbers ("18.11.2026", "2026-11-18") get times only too.
    @Test func overnightShowsTimesOnlyInNumericDateLocales() {
        for id in ["de_DE", "en_CA", "sv_SE", "ko_KR"] {
            let t = plain(EventTimeText.range(event("e", "2026-11-18T23:00:00Z", "2026-11-19T01:00:00Z"),
                                              calendar: utc, locale: Locale(identifier: id)))
            #expect(!t.contains("2026") && !t.contains("18") && !t.contains("19"), "\(id): \(t)")
        }
    }

    /// An event ending at midnight ends on the next day: times only.
    @Test func endingAtMidnightShowsTimesOnly() {
        let t = plain(EventTimeText.range(event("e", "2026-11-19T20:00:00Z", "2026-11-20T00:00:00Z"),
                                          calendar: utc, locale: Locale(identifier: "de_DE")))
        #expect(t.contains("20:00") && t.contains("00:00") && !t.contains("2026"), "\(t)")
    }

    @Test func spokenRange() {
        let t = plain(EventTimeText.spoken(event("e", "2026-11-19T13:30:00Z", "2026-11-19T15:47:00Z"), calendar: utc, locale: us))
        #expect(t == "1:30 PM to 3:47 PM", "\(t)")
    }
}
