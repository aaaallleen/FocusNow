import Foundation

/// Where AppKit keeps a window's saved place: "NSWindow Frame <autosave name>".
public enum WindowFrames {
    /// Gives a window that took over from another (the main window replaced the
    /// Stats window) the old one's saved place, unless it already has its own.
    public static func carryOver(from old: String, to new: String, in defaults: UserDefaults) {
        let newKey = "NSWindow Frame \(new)"
        guard defaults.object(forKey: newKey) == nil,
              let frame = defaults.string(forKey: "NSWindow Frame \(old)") else { return }
        defaults.set(frame, forKey: newKey)
    }
}
