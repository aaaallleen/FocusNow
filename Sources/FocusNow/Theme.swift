import AppKit
import FocusNowCore
import SwiftUI

/// The app's motion values, and the colours of the chosen colourway.
///
/// Colours come from `AppearancePreferences`: the window and popover roots put
/// the palette in the environment, and views read it through `ThemeColors`.
/// Nothing hard-codes the teal or amber any more.
enum Theme {
    static let track = Color(nsColor: .quaternaryLabelColor)

    static let pressScale: CGFloat = 0.97
    static let pressDuration: Double = 0.15
    static let phaseFade: Double = 0.2

    /// For things arriving: quick to start, soft to land (cubic-bezier 0.23, 1, 0.32, 1).
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}

/// Shakes its content sideways once each time `trigger` goes up: the macOS
/// "that didn't work", for typed text that can't be read, so a value that
/// snapped back isn't mistaken for one that was applied even with the sound
/// off. With Reduce Motion it dims for a moment in place instead.
struct RejectShake: ViewModifier {
    let trigger: Int
    /// How far the first swing goes, in points.
    var distance: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Frame {
        var x: CGFloat = 0
        var opacity: Double = 1
    }

    func body(content: Content) -> some View {
        // 0 → −1 → 0.83 → −0.5 → 0.33 → 0 of `distance`, over 0.3 s; each
        // swing eases in and out, so it never goes past these.
        let swing = reduceMotion ? 0 : distance
        content.keyframeAnimator(initialValue: Frame(), trigger: trigger) { view, frame in
            view.offset(x: frame.x).opacity(frame.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                LinearKeyframe(-swing, duration: 0.05, timingCurve: .easeInOut)
                LinearKeyframe(swing * 0.83, duration: 0.06, timingCurve: .easeInOut)
                LinearKeyframe(-swing * 0.5, duration: 0.06, timingCurve: .easeInOut)
                LinearKeyframe(swing * 0.33, duration: 0.06, timingCurve: .easeInOut)
                LinearKeyframe(0, duration: 0.07, timingCurve: .easeOut)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(reduceMotion ? 0.4 : 1, duration: 0.12, timingCurve: .easeInOut)
                LinearKeyframe(1, duration: 0.18, timingCurve: .easeOut)
            }
        }
    }
}

extension EnvironmentValues {
    /// The chosen colourway's colours; the window and popover roots set it.
    @Entry var palette: Palette = Colorway.standard.palette
}

/// The palette's colours for one mode. Views build it from the environment's
/// palette and colour scheme, so a subtree forced into light or dark (the
/// Appearance preview) gets that mode's colours.
struct ThemeColors {
    let palette: Palette
    let dark: Bool

    init(_ palette: Palette, dark: Bool) {
        self.palette = palette
        self.dark = dark
    }

    init(_ palette: Palette, scheme: ColorScheme) {
        self.init(palette, dark: scheme == .dark)
    }

    var focus: Color { Color(palette.focus(dark: dark)) }
    var rest: Color { Color(palette.rest(dark: dark)) }

    func color(for kind: SessionKind) -> Color { kind.isBreak ? rest : focus }

    /// Text on a fill of the phase colour: white or near-black, whichever reads better.
    func text(on kind: SessionKind) -> Color {
        Self.textColor(on: kind.isBreak ? palette.rest(dark: dark) : palette.focus(dark: dark))
    }

    /// Text on a fill of the focus colour.
    var onFocus: Color { Self.textColor(on: palette.focus(dark: dark)) }

    static func textColor(on fill: SRGBColor) -> Color {
        TextOnColor.best(on: fill) == .white ? .white : Color(TextOnColor.darkColor)
    }
}

extension Color {
    init(_ rgb: SRGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension NSColor {
    /// A colour that resolves to `light` or `dark` by the appearance it's drawn in.
    static func dynamic(light: SRGBColor, dark: SRGBColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.isDark ? dark : light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
    }
}

extension SRGBColor {
    /// The colour in sRGB, or nil when it can't be converted (a pattern image).
    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
