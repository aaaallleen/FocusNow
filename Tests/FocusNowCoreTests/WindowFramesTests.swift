import Foundation
import Testing
@testable import FocusNowCore

struct WindowFramesTests {
    let defaults = freshDefaults()
    let old = "NSWindow Frame FocusStatsWindow"
    let new = "NSWindow Frame FocusNowMainWindow"

    @Test func theOldWindowsPlaceCarriesOverToTheNewOne() {
        defaults.set("900 616 760 588 0 0 2560 1410 ", forKey: old)
        WindowFrames.carryOver(from: "FocusStatsWindow", to: "FocusNowMainWindow", in: defaults)
        #expect(defaults.string(forKey: new) == "900 616 760 588 0 0 2560 1410 ")
    }

    @Test func aPlaceAlreadySavedForTheNewWindowIsKept() {
        defaults.set("900 616 760 588 0 0 2560 1410 ", forKey: old)
        defaults.set("10 20 800 600 0 0 2560 1410 ", forKey: new)
        WindowFrames.carryOver(from: "FocusStatsWindow", to: "FocusNowMainWindow", in: defaults)
        #expect(defaults.string(forKey: new) == "10 20 800 600 0 0 2560 1410 ")
    }

    @Test func nothingToCarryOverLeavesNothing() {
        WindowFrames.carryOver(from: "FocusStatsWindow", to: "FocusNowMainWindow", in: defaults)
        #expect(defaults.object(forKey: new) == nil)
    }
}
