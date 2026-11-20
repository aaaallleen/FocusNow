import Foundation
import Testing
@testable import FocusNowCore

struct SelfCheckGateTests {
    @Test func needsBothTheSnapshotAndTheSeparateDataFolder() {
        let env = ["FOCUSNOW_SNAPSHOT_DIR": "/tmp/shots", "FOCUSNOW_DATA_DIR": "/tmp/data"]
        #expect(SelfCheckGate.directory(in: env) == URL(fileURLWithPath: "/tmp/shots"))
    }

    @Test func neverRunsAgainstRealData() {
        #expect(SelfCheckGate.directory(in: ["FOCUSNOW_SNAPSHOT_DIR": "/tmp/shots"]) == nil)
        #expect(SelfCheckGate.directory(in: ["FOCUSNOW_SNAPSHOT_DIR": "/tmp/shots", "FOCUSNOW_DATA_DIR": ""]) == nil)
    }

    @Test func offByDefault() {
        #expect(SelfCheckGate.directory(in: [:]) == nil)
        #expect(SelfCheckGate.directory(in: ["FOCUSNOW_DATA_DIR": "/tmp/data"]) == nil)
    }
}
