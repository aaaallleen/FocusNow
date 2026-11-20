import Testing
@testable import FocusNowCore

struct TimeFormatTests {
    @Test func clockShowsMinutesAndSeconds() {
        #expect(TimeFormat.clock(2400) == "40:00")
        #expect(TimeFormat.clock(1122) == "18:42")
        #expect(TimeFormat.clock(65) == "01:05")
        #expect(TimeFormat.clock(0) == "00:00")
    }

    @Test func clockAddsHoursPastAnHour() {
        #expect(TimeFormat.clock(3900) == "1:05:00")
        #expect(TimeFormat.clock(10_800) == "3:00:00")
    }

    @Test func clockNeverGoesNegative() {
        #expect(TimeFormat.clock(-5) == "00:00")
    }

    @Test func durationShowsHoursAndMinutes() {
        #expect(TimeFormat.duration(7800) == "2h 10m")
        #expect(TimeFormat.duration(2700) == "45m")
        #expect(TimeFormat.duration(0) == "0m")
        #expect(TimeFormat.duration(59) == "0m")
        #expect(TimeFormat.duration(14_400) == "4h")
        #expect(TimeFormat.duration(512 * 3600) == "512h")
    }
}
