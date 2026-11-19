import Testing
@testable import FocusNowCore

struct LengthInputTests {
    @Test func minutesAcceptsNumbersWithOrWithoutAUnit() {
        for text in ["25", " 25 ", "25m", "25 m", "25min", "25 min", "25 Minutes", "25 mins"] {
            #expect(LengthInput.minutes(text, in: 1...180) == 25, "\(text)")
        }
        #expect(LengthInput.minutes("1 minute", in: 1...180) == 1)
    }

    @Test func minutesClampToTheRange() {
        #expect(LengthInput.minutes("0", in: 1...180) == 1)
        #expect(LengthInput.minutes("999", in: 1...180) == 180)
    }

    @Test func minutesRejectEverythingElse() {
        for text in ["", "  ", "abc", "-5", "2.5", "25:00", "1:30", "25h", "m"] {
            #expect(LengthInput.minutes(text, in: 1...180) == nil, "\(text)")
        }
    }

    @Test func sessionsAcceptCountsWithOrWithoutAUnit() {
        #expect(LengthInput.sessions("4", in: 1...12) == 4)
        #expect(LengthInput.sessions("4 sessions", in: 1...12) == 4)
        #expect(LengthInput.sessions("1 session", in: 1...12) == 1)
        #expect(LengthInput.sessions("0", in: 1...12) == 1)
        #expect(LengthInput.sessions("99", in: 1...12) == 12)
        #expect(LengthInput.sessions("4 min", in: 1...12) == nil)
        #expect(LengthInput.sessions("x", in: 1...12) == nil)
    }

    @Test func goalAcceptsHoursAndMinutesInCommonForms() {
        let cases: [(String, Int)] = [
            ("4h", 14_400), ("4", 14_400), ("4 h", 14_400), ("3h 30m", 12_600), ("3h30m", 12_600),
            ("3:30", 12_600), ("0:45", 2_700), ("90m", 5_400), ("90 min", 5_400),
            ("1.5h", 5_400), ("1.5", 5_400), ("2H 15M", 8_100),
        ]
        for (text, seconds) in cases { #expect(LengthInput.goalSeconds(text) == seconds, "\(text)") }
    }

    @Test func goalClampsToFifteenMinutesThroughSixteenHours() {
        #expect(LengthInput.goalSeconds("5m") == 900)
        #expect(LengthInput.goalSeconds("20h") == 57_600)
    }

    @Test func hugeNumbersClampInsteadOfCrashing() {
        #expect(LengthInput.minutes("99999999999999999999", in: 1...180) == 180)
        #expect(LengthInput.sessions("99999999999999999999", in: 1...12) == 12)
        for text in ["99999999999999999999", "9000000000000000000h", "9000000000000000000:00",
                     "9000000000000000000m", "9000000000000000000h 5m"] {
            #expect(LengthInput.goalSeconds(text) == 57_600, "\(text)")
        }
    }

    @Test func fullWidthAndOtherScriptDigitsReadAsNumbers() {
        #expect(LengthInput.minutes("２５", in: 1...180) == 25)
        #expect(LengthInput.minutes("٢٥", in: 1...180) == 25)
        #expect(LengthInput.minutes("２５ｍｉｎ", in: 1...180) == 25)
        #expect(LengthInput.sessions("４", in: 1...12) == 4)
        #expect(LengthInput.goalSeconds("３ｈ") == 10_800)
        #expect(LengthInput.goalSeconds("３：３０") == 12_600)
        #expect(LengthInput.goalSeconds("١.٥") == 5_400)
    }

    @Test func goalRejectsEverythingElse() {
        for text in ["", "abc", "h", "3:75", "-2h", "4 sessions", "3:"] {
            #expect(LengthInput.goalSeconds(text) == nil, "\(text)")
        }
    }
}
