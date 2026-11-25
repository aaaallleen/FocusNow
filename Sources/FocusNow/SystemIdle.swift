import CoreGraphics
import Foundation

/// How long since the owner last used the keyboard, mouse or trackpad. Read
/// from the window server's own record, so it needs no permission.
enum SystemIdle {
    static func seconds() -> TimeInterval {
        // ~0 is kCGAnyInputEventType: any kind of input counts.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
