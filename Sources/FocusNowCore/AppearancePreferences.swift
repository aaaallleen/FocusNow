import Foundation
import Observation

/// Light or dark for FocusNow's window and popover, or whatever the Mac uses.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark
}

/// Settings → Appearance: the light/dark mode and the colourway.
///
/// Each value has its own UserDefaults key, apart from `TimerSettings` (see
/// `CalendarPreferences`). A value that's missing, the wrong type or damaged
/// falls back to its own default and leaves the others alone.
@MainActor @Observable
public final class AppearancePreferences {
    public static let modeKey = "appearance.mode"
    public static let colorwayKey = "appearance.colorway"
    /// The custom colours, as four hex strings in `PaletteSlot` order.
    public static let customKey = "appearance.customColors"
    /// The `colorwayID` while the owner's own colours are chosen.
    public static let customID = "custom"

    @ObservationIgnored private let defaults: UserDefaults

    public var mode: AppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// A preset's ID, or `customID`.
    public private(set) var colorwayID: String {
        didSet { defaults.set(colorwayID, forKey: Self.colorwayKey) }
    }

    /// The owner's own colours; nil until Custom is first chosen. Kept while a
    /// preset is chosen, so choosing Custom again brings them back.
    public private(set) var custom: Palette? {
        didSet { defaults.set(custom?.hexes, forKey: Self.customKey) }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        mode = (defaults.object(forKey: Self.modeKey) as? String).flatMap(AppearanceMode.init) ?? .system
        let custom = (defaults.object(forKey: Self.customKey) as? [String]).flatMap(Palette.init(hexes:))
        self.custom = custom
        let id = defaults.object(forKey: Self.colorwayKey) as? String
        if let id, Colorway.preset(id: id) != nil || (id == Self.customID && custom != nil) {
            colorwayID = id
        } else {
            colorwayID = Colorway.standard.id
        }
    }

    /// The colours in use: the chosen preset's, or the custom ones.
    public var palette: Palette {
        if colorwayID == Self.customID, let custom { return custom }
        return (Colorway.preset(id: colorwayID) ?? Colorway.standard).palette
    }

    /// Unknown IDs are ignored.
    public func choosePreset(_ id: String) {
        guard Colorway.preset(id: id) != nil else { return }
        colorwayID = id
    }

    /// The first time, the custom colours start as the colourway that was chosen.
    public func chooseCustom() {
        if custom == nil { custom = palette }
        colorwayID = Self.customID
    }

    /// Changes one custom colour, choosing Custom first if it isn't chosen.
    public func setCustom(_ color: SRGBColor, for slot: PaletteSlot) {
        chooseCustom()
        custom?[slot] = color
    }
}
