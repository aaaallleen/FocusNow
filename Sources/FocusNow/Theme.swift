import AppKit
import FocusNowCore
import SwiftUI

/// The only place the app's colours and motion values are defined. Colours are
/// taken from the app icon: teal for focus, warm cream-amber for rest.
enum Theme {
    static let focusNS = NSColor(name: "focus") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.42, green: 0.69, blue: 0.79, alpha: 1) // #6BB0C9
            : NSColor(srgbRed: 0.20, green: 0.42, blue: 0.51, alpha: 1) // #336B82
    }
    static let restNS = NSColor(name: "rest") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.91, green: 0.73, blue: 0.40, alpha: 1) // #E9BA66
            : NSColor(srgbRed: 0.80, green: 0.58, blue: 0.20, alpha: 1) // #CC9433
    }

    static let focus = Color(nsColor: focusNS)
    static let rest = Color(nsColor: restNS)
    static let track = Color(nsColor: .quaternaryLabelColor)

    static func color(for kind: SessionKind) -> Color { kind.isBreak ? rest : focus }

    static let pressScale: CGFloat = 0.97
    static let pressDuration: Double = 0.15
    static let phaseFade: Double = 0.2
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
