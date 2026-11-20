import Testing
@testable import FocusNowCore

struct ColorwayTests {
    @Test func eightPresetsInOrder() {
        #expect(Colorway.presets.map(\.id) == ["teal", "sage", "indigo", "plum", "ocean", "forest", "rose", "graphite"])
        #expect(Colorway.presets.map(\.name) == ["Teal & Amber", "Sage & Clay", "Indigo & Peach", "Plum & Gold",
                                                  "Ocean & Coral", "Forest & Rust", "Rose & Mint", "Graphite & Citron"])
        #expect(Colorway.standard.id == "teal")
        #expect(Colorway.preset(id: "ocean")?.name == "Ocean & Coral")
        #expect(Colorway.preset(id: "neon") == nil)
    }

    @Test func presetValuesMatchTheSpec() {
        let expected: [String: [String]] = [
            "teal": ["#336B82", "#6BB0C9", "#CC9433", "#E9BA66"],
            "sage": ["#4E7A5B", "#8FBF9B", "#C0704A", "#E59B79"],
            "indigo": ["#4A54A6", "#939BEB", "#D27F57", "#F2AB88"],
            "plum": ["#7B4B87", "#C696D2", "#B38A2A", "#E3C264"],
            "ocean": ["#1F6DAE", "#6DAFE9", "#D85F57", "#F29C94"],
            "forest": ["#2E6A4E", "#76B996", "#B0532C", "#E38C66"],
            "rose": ["#A8476A", "#E58DAA", "#3A9580", "#7ACFB9"],
            "graphite": ["#474D56", "#BAC1CB", "#8E9C2E", "#C9D86B"],
        ]
        for way in Colorway.presets {
            #expect(way.palette.hexes == expected[way.id], "\(way.id)")
        }
    }

    @Test func hexParsing() {
        #expect(RGBColor(hex: "336b82")?.hex == "#336B82")
        #expect(RGBColor(hex: "#336B82")?.hex == "#336B82")
        #expect(RGBColor(hex: "#12345") == nil)
        #expect(RGBColor(hex: "zzzzzz") == nil)
        #expect(RGBColor(hex: "") == nil)
    }

    @Test func clampsOutOfRangeComponents() {
        #expect(RGBColor(red: 1.2, green: -0.1, blue: 0.5).hex == "#FF0080")
    }

    @Test func textPicksTheMoreReadable() {
        #expect(TextOnColor.best(on: RGBColor(hex: "#336B82")!) == .white)
        #expect(TextOnColor.best(on: RGBColor(hex: "#E9BA66")!) == .dark)
        #expect(TextOnColor.best(on: RGBColor(hex: "#6BB0C9")!) == .dark)
        #expect(TextOnColor.best(on: RGBColor(hex: "#000000")!) == .white)
        #expect(TextOnColor.best(on: RGBColor(hex: "#FFFFFF")!) == .dark)
    }

    @Test func paletteSlotsAndHexes() {
        var p = Colorway.standard.palette
        p[.breakDark] = RGBColor(hex: "#112233")!
        #expect(p.rest(dark: true).hex == "#112233")
        #expect(p.focus(dark: false).hex == "#336B82")
        #expect(Palette(hexes: p.hexes) == p)
        #expect(Palette(hexes: ["#336B82", "#6BB0C9", "#CC9433"]) == nil)
        #expect(Palette(hexes: ["#336B82", "#6BB0C9", "#CC9433", "nope"]) == nil)
    }
}
