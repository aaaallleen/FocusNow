import Foundation

/// An opaque sRGB colour, each component 0...1.
public struct RGBColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    /// Components outside 0...1 (a wide-gamut colour converted to sRGB) are clamped.
    public init(red: Double, green: Double, blue: Double) {
        func clamp(_ v: Double) -> Double { v.isNaN ? 0 : min(max(v, 0), 1) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
    }

    /// "#RRGGBB" or "RRGGBB", any case.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = Int(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// "#RRGGBB", uppercase.
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// WCAG relative luminance: 0 for black, 1 for white.
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.039_28 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio against `other`, 1...21.
    public func contrast(with other: RGBColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Text drawn on a colour fill: white, or near-black (#141414).
public enum TextOnColor: Equatable, Sendable {
    case white, dark

    public static let darkColor = RGBColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255)

    /// Whichever has more contrast against `color`.
    public static func best(on color: RGBColor) -> TextOnColor {
        let white = RGBColor(red: 1, green: 1, blue: 1)
        return color.contrast(with: white) >= color.contrast(with: darkColor) ? .white : .dark
    }
}

/// The four colours of a colourway, in the order Settings lists them.
public enum PaletteSlot: Int, CaseIterable, Sendable {
    case focusLight, focusDark, breakLight, breakDark
}

/// A focus colour and a break colour, each with a light- and a dark-mode shade.
public struct Palette: Equatable, Sendable {
    public var focusLight: RGBColor
    public var focusDark: RGBColor
    public var breakLight: RGBColor
    public var breakDark: RGBColor

    public init(focusLight: RGBColor, focusDark: RGBColor, breakLight: RGBColor, breakDark: RGBColor) {
        self.focusLight = focusLight
        self.focusDark = focusDark
        self.breakLight = breakLight
        self.breakDark = breakDark
    }

    /// Exactly four valid hex colours, in `PaletteSlot` order.
    public init?(hexes: [String]) {
        let colors = hexes.compactMap(RGBColor.init(hex:))
        guard hexes.count == 4, colors.count == 4 else { return nil }
        self.init(focusLight: colors[0], focusDark: colors[1], breakLight: colors[2], breakDark: colors[3])
    }

    public subscript(slot: PaletteSlot) -> RGBColor {
        get {
            switch slot {
            case .focusLight: focusLight
            case .focusDark: focusDark
            case .breakLight: breakLight
            case .breakDark: breakDark
            }
        }
        set {
            switch slot {
            case .focusLight: focusLight = newValue
            case .focusDark: focusDark = newValue
            case .breakLight: breakLight = newValue
            case .breakDark: breakDark = newValue
            }
        }
    }

    public func focus(dark: Bool) -> RGBColor { dark ? focusDark : focusLight }
    public func rest(dark: Bool) -> RGBColor { dark ? breakDark : breakLight }

    /// The four colours as hex, in `PaletteSlot` order.
    public var hexes: [String] { PaletteSlot.allCases.map { self[$0].hex } }
}

/// A named palette Settings offers.
public struct Colorway: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var palette: Palette

    public init(id: String, name: String, palette: Palette) {
        self.id = id
        self.name = name
        self.palette = palette
    }

    private static func make(_ id: String, _ name: String, _ hexes: [String]) -> Colorway {
        Colorway(id: id, name: name, palette: Palette(hexes: hexes)!)
    }

    /// The eight presets, in the order Settings shows them. Teal & Amber is the
    /// app's original colours, from the icon.
    public static let presets: [Colorway] = [
        make("teal", "Teal & Amber", ["#336B82", "#6BB0C9", "#CC9433", "#E9BA66"]),
        make("sage", "Sage & Clay", ["#4E7A5B", "#8FBF9B", "#C0704A", "#E59B79"]),
        make("indigo", "Indigo & Peach", ["#4A54A6", "#939BEB", "#D27F57", "#F2AB88"]),
        make("plum", "Plum & Gold", ["#7B4B87", "#C696D2", "#B38A2A", "#E3C264"]),
        make("ocean", "Ocean & Coral", ["#1F6DAE", "#6DAFE9", "#D85F57", "#F29C94"]),
        make("forest", "Forest & Rust", ["#2E6A4E", "#76B996", "#B0532C", "#E38C66"]),
        make("rose", "Rose & Mint", ["#A8476A", "#E58DAA", "#3A9580", "#7ACFB9"]),
        make("graphite", "Graphite & Citron", ["#474D56", "#BAC1CB", "#8E9C2E", "#C9D86B"]),
    ]

    /// The default: Teal & Amber.
    public static var standard: Colorway { presets[0] }

    public static func preset(id: String) -> Colorway? {
        presets.first { $0.id == id }
    }
}
