import Foundation

/// Decides whether the development self-check may run. It writes fake history
/// and changes settings, so it only runs when the app was also pointed at a
/// separate data folder (FOCUSNOW_DATA_DIR): never against real data.
public enum SelfCheckGate {
    public static func directory(in environment: [String: String]) -> URL? {
        guard let snapshots = environment["FOCUSNOW_SNAPSHOT_DIR"], !snapshots.isEmpty,
              let data = environment["FOCUSNOW_DATA_DIR"], !data.isEmpty else { return nil }
        return URL(fileURLWithPath: snapshots)
    }
}
