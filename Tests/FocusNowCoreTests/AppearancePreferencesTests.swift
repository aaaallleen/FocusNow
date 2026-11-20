import Foundation
import Testing
@testable import FocusNowCore

@MainActor
struct AppearancePreferencesTests {
    @Test func defaults() {
        let p = AppearancePreferences(defaults: freshDefaults())
        #expect(p.mode == .system)
        #expect(p.colorwayID == "teal")
        #expect(p.custom == nil)
        #expect(p.palette == Colorway.standard.palette)
    }

    @Test func persists() {
        let d = freshDefaults()
        let p = AppearancePreferences(defaults: d)
        p.mode = .dark
        p.choosePreset("ocean")
        let q = AppearancePreferences(defaults: d)
        #expect(q.mode == .dark)
        #expect(q.colorwayID == "ocean")
        #expect(q.palette == Colorway.preset(id: "ocean")!.palette)
    }

    @Test func damagedValuesFallBack() {
        let d = freshDefaults()
        d.set(5, forKey: AppearancePreferences.modeKey)
        d.set(["x"], forKey: AppearancePreferences.colorwayKey)
        d.set("nope", forKey: AppearancePreferences.customKey)
        d.set(true, forKey: CalendarPreferences.showOnTimerPageKey)
        let p = AppearancePreferences(defaults: d)
        #expect(p.mode == .system)
        #expect(p.colorwayID == "teal")
        #expect(p.custom == nil)
        #expect(d.bool(forKey: CalendarPreferences.showOnTimerPageKey)) // untouched
    }

    @Test func unknownColorwayLoadsAsTeal() {
        let d = freshDefaults()
        d.set("neon", forKey: AppearancePreferences.colorwayKey)
        #expect(AppearancePreferences(defaults: d).colorwayID == "teal")
    }

    @Test func customWithDamagedColorsLoadsAsTeal() {
        let d = freshDefaults()
        d.set("custom", forKey: AppearancePreferences.colorwayKey)
        d.set(["#336B82", "#6BB0C9", "#CC9433"], forKey: AppearancePreferences.customKey)
        let p = AppearancePreferences(defaults: d)
        #expect(p.colorwayID == "teal")
        #expect(p.custom == nil)
    }

    @Test func customStartsFromThePickedPreset() {
        let p = AppearancePreferences(defaults: freshDefaults())
        p.choosePreset("sage")
        p.chooseCustom()
        #expect(p.colorwayID == AppearancePreferences.customID)
        #expect(p.custom == Colorway.preset(id: "sage")!.palette)
        #expect(p.palette == Colorway.preset(id: "sage")!.palette)
    }

    @Test func customIsKeptAfterSwitchingAway() {
        let d = freshDefaults()
        let p = AppearancePreferences(defaults: d)
        p.setCustom(RGBColor(hex: "#112233")!, for: .focusLight)
        #expect(p.colorwayID == AppearancePreferences.customID)
        p.choosePreset("ocean")
        p.chooseCustom()
        #expect(p.palette.focusLight.hex == "#112233")
        #expect(AppearancePreferences(defaults: d).palette.focusLight.hex == "#112233")
    }

    @Test func unknownPresetIsIgnored() {
        let p = AppearancePreferences(defaults: freshDefaults())
        p.choosePreset("plum")
        p.choosePreset("neon")
        #expect(p.colorwayID == "plum")
    }
}
