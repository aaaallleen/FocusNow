# FocusNow Appearance and Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings → Appearance (System / Light / Dark, 8 preset colourways and a custom one), the colourway applied everywhere, two-row timer buttons, room around the ring at every size, a set focus length that stays, right-aligned Cycle units, event time ranges, and the app icon built from `icon.svg`.

**Architecture:**
- **Core (`FocusNowCore`, unit-tested with Swift Testing):**
  - colour values, palettes, the 8 presets and the text-on-colour rule (`Colorway.swift`);
  - the `@Observable AppearancePreferences` store;
  - which timer control goes in which row (`TimerControls.swift`);
  - the set focus length kept in the engine and its snapshot;
  - event time-range text.
- **App target, checked by the self-check:**
  - views read the palette from a SwiftUI environment value that the window and popover roots set from `AppearancePreferences`;
  - AppKit pieces (the menu bar item, `NSApp.appearance`, the popover) are driven from `AppDelegate`.

**Tech Stack:** Swift 6 package (tools 6.0), SwiftUI + AppKit, Swift Charts, Swift Testing, bash; AppKit's SVG support for the icon script.

**Spec:** `docs/superpowers/specs/2026-11-19-focusnow-improvements-design.md` (builds on the v1, timer-page, settings-tab and calendar specs in the same folder).

## Global Constraints

- macOS 14+, Swift 6, Apple frameworks only, no new dependencies.
- New preferences live under their own UserDefaults keys: `appearance.mode`, `appearance.colorway`, `appearance.customColors`. They are never added to `TimerSettings`. Each falls back to its own default when missing, the wrong type, or damaged.
- Self-check:
  - It runs only against `FOCUSNOW_DATA_DIR` and the `local.focusnow.app.testing` defaults suite.
  - It never replaces or quits `/Applications/FocusNow.app`.
  - It never opens the macOS colour panel, activates other apps, or touches the login keychain.
- Copy, exactly as written (US spelling in the UI):
  - Settings sidebar: "Cycle", "Goal", "General", "Calendar", "Appearance". Appearance uses the `paintpalette` symbol.
  - The mode control: "Appearance", with "System", "Light", "Dark".
  - Section headers: "Colorway", "Your colors", "Preview". Tiles: the eight preset names, then "Custom".
  - Colour 1: "Focus, light mode" — "The ring and the main button during focus, the goal bar, the Stats charts and calendar blocks, and the Settings sidebar icons, in light mode."
  - Colour 2: "Focus, dark mode" — "The same places as color 1, in dark mode."
  - Colour 3: "Break, light mode" — "The ring and the main button during a short or long break, and the menu bar timer during a break, in light mode."
  - Colour 4: "Break, dark mode" — "The same places as color 3, in dark mode."
  - Note: "Custom starts from the colorway you had picked. Button text switches between black and white to stay readable."
  - Event rows: "Now". "until …" and "to …" go away.
- Values:
  - Presets, in this order (ID, name, focus light, focus dark, break light, break dark):
    - teal, Teal & Amber, #336B82, #6BB0C9, #CC9433, #E9BA66
    - sage, Sage & Clay, #4E7A5B, #8FBF9B, #C0704A, #E59B79
    - indigo, Indigo & Peach, #4A54A6, #939BEB, #D27F57, #F2AB88
    - plum, Plum & Gold, #7B4B87, #C696D2, #B38A2A, #E3C264
    - ocean, Ocean & Coral, #1F6DAE, #6DAFE9, #D85F57, #F29C94
    - forest, Forest & Rust, #2E6A4E, #76B996, #B0532C, #E38C66
    - rose, Rose & Mint, #A8476A, #E58DAA, #3A9580, #7ACFB9
    - graphite, Graphite & Citron, #474D56, #BAC1CB, #8E9C2E, #C9D86B
  - Defaults: System mode and Teal & Amber. The "dark" text colour is #141414.
  - The gap above and below the ring is at least 22 pt.
- Icon files (`icon.svg`, `icon.png`, `Resources/Icon/`) are never committed.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The unit test command is `swift test 2>&1 | tail -3`. 188 tests pass before Task 1.

## Review Focus

1. **The menu bar item and popover under a forced mode.** With Light or Dark forced, the menu bar item must keep following the real menu bar, and the popover must follow the forced mode. An `NSPopover` otherwise takes its look from the status button. Task 3: self-check lines comparing effective appearances.
2. **Custom colours from other colour spaces.** Wide-gamut (P3), grey-slider and named colours from the colour panel must convert without crashing. Out-of-range sRGB components are clamped. Task 1: `clampsOutOfRangeComponents`. Task 4: a converter that keeps the previous colour when conversion fails.
3. **Damaged or foreign stored appearance values** load as defaults and leave every other preference alone. Task 2: `damagedValuesFallBack`.
4. **The Focus default changed while the app was closed.** A length set against the old default must not come back. Task 7: `relaunchWithAChangedFocusDefaultDropsTheLength`.
5. **The 640 × 480 window with three event rows and both button rows.** Everything fits, the ring is at least 120 pt, and the gaps around it are at least 22 pt. Task 6: a self-check line at that size with events shown.

---

### Task 1: Colours, palettes and the presets

**Files:**
- Create: `Sources/FocusNowCore/Colorway.swift`
- Test: `Tests/FocusNowCoreTests/ColorwayTests.swift`

**Interfaces:**
- Produces:
  - `public struct RGBColor: Equatable, Codable, Sendable`, with:
    - `red`, `green` and `blue` as `Double`, clamped to 0...1 by `init(red:green:blue:)`;
    - `init?(hex: String)`, which accepts "#RRGGBB" or "RRGGBB" in any case;
    - `var hex: String`, uppercase "#RRGGBB" with each component rounded to the nearest 1/255;
    - `var luminance: Double`, the WCAG relative luminance.
  - `public enum TextOnColor: Equatable, Sendable { case white, dark }` and `static func best(on: RGBColor) -> TextOnColor`. It picks whichever of white or #141414 has the higher WCAG contrast ratio against the colour.
  - `public enum PaletteSlot: Int, CaseIterable, Sendable { case focusLight, focusDark, breakLight, breakDark }`
  - `public struct Palette: Equatable, Sendable`, with:
    - `var focusLight, focusDark, breakLight, breakDark: RGBColor` and the memberwise `init`;
    - `subscript(slot: PaletteSlot) -> RGBColor { get set }`;
    - `func focus(dark: Bool) -> RGBColor` and `func rest(dark: Bool) -> RGBColor`;
    - `var hexes: [String]` in slot order;
    - `init?(hexes: [String])`, which needs exactly 4 valid hexes.
  - `public struct Colorway: Identifiable, Equatable, Sendable`, with:
    - `id: String`, `name: String` and `palette: Palette`;
    - `static let presets: [Colorway]`, the 8 presets in Global Constraints order;
    - `static var standard: Colorway`, which is teal;
    - `static func preset(id: String) -> Colorway?`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func eightPresetsInOrder() {
    #expect(Colorway.presets.map(\.id) == ["teal", "sage", "indigo", "plum", "ocean", "forest", "rose", "graphite"])
    #expect(Colorway.presets.map(\.name) == ["Teal & Amber", "Sage & Clay", "Indigo & Peach", "Plum & Gold",
                                              "Ocean & Coral", "Forest & Rust", "Rose & Mint", "Graphite & Citron"])
    #expect(Colorway.standard.id == "teal")
}
@Test func presetValuesMatchTheSpec() {
    let expected: [String: [String]] = [
        "teal": ["#336B82", "#6BB0C9", "#CC9433", "#E9BA66"], "sage": ["#4E7A5B", "#8FBF9B", "#C0704A", "#E59B79"],
        "indigo": ["#4A54A6", "#939BEB", "#D27F57", "#F2AB88"], "plum": ["#7B4B87", "#C696D2", "#B38A2A", "#E3C264"],
        "ocean": ["#1F6DAE", "#6DAFE9", "#D85F57", "#F29C94"], "forest": ["#2E6A4E", "#76B996", "#B0532C", "#E38C66"],
        "rose": ["#A8476A", "#E58DAA", "#3A9580", "#7ACFB9"], "graphite": ["#474D56", "#BAC1CB", "#8E9C2E", "#C9D86B"]]
    for way in Colorway.presets { #expect(way.palette.hexes == expected[way.id]) }
}
@Test func hexParsing() {
    #expect(RGBColor(hex: "336b82")?.hex == "#336B82")
    #expect(RGBColor(hex: "#12345") == nil); #expect(RGBColor(hex: "zzzzzz") == nil); #expect(RGBColor(hex: "") == nil)
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
    #expect(p.rest(dark: true).hex == "#112233"); #expect(p.focus(dark: false).hex == "#336B82")
    #expect(Palette(hexes: p.hexes) == p)
    #expect(Palette(hexes: ["#336B82", "#6BB0C9", "#CC9433"]) == nil)
    #expect(Palette(hexes: ["#336B82", "#6BB0C9", "#CC9433", "nope"]) == nil)
}
```

- [ ] **Step 2: Run them and watch them fail.** Run: `swift test --filter ColorwayTests 2>&1 | tail -5`. Expected: a build failure, because `Colorway` and `RGBColor` don't exist.
- [ ] **Step 3: Implement `Colorway.swift`** using the interfaces above.
- [ ] **Step 4: Run them and watch them pass.** Run: `swift test --filter ColorwayTests 2>&1 | tail -3`. Expected: all pass. Then `swift test 2>&1 | tail -3` → 194 pass.
- [ ] **Step 5: Commit.** `git add Sources/FocusNowCore/Colorway.swift Tests/FocusNowCoreTests/ColorwayTests.swift && git commit -m "feat: colourway presets and colour values"`

### Task 2: The Appearance store

**Files:**
- Create: `Sources/FocusNowCore/AppearancePreferences.swift`
- Test: `Tests/FocusNowCoreTests/AppearancePreferencesTests.swift`

**Interfaces:**
- Consumes: Task 1's `Palette`, `PaletteSlot`, `RGBColor` and `Colorway`.
- Produces:
  - `public enum AppearanceMode: String, CaseIterable, Sendable { case system, light, dark }`
  - `@MainActor @Observable public final class AppearancePreferences`, with:
    - the keys `static let modeKey = "appearance.mode"`, `colorwayKey = "appearance.colorway"`, `customKey = "appearance.customColors"` (stored as 4 hex strings), and `static let customID = "custom"`;
    - `var mode: AppearanceMode`, which persists on set;
    - `private(set) var colorwayID: String`, either a preset ID or `customID`;
    - `private(set) var custom: Palette?`;
    - `init(defaults: UserDefaults)`;
    - `var palette: Palette`: the chosen preset's palette, or `custom` when Custom is chosen;
    - `func choosePreset(_ id: String)`, which ignores unknown IDs;
    - `func chooseCustom()`, which copies the current palette into `custom` when it's nil, then chooses Custom;
    - `func setCustom(_ color: RGBColor, for slot: PaletteSlot)`, which chooses Custom first (seeding as `chooseCustom` does), then sets the slot.
  - Loading rules:
    - an unknown mode loads as `.system`;
    - an unknown colourway ID loads as "teal";
    - "custom" with missing or damaged colours loads as "teal", with `custom` nil.

- [ ] **Step 1: Write the failing tests** (use `freshDefaults()` from `TestSupport.swift`)

```swift
@Test func defaults() {
    let p = AppearancePreferences(defaults: freshDefaults())
    #expect(p.mode == .system); #expect(p.colorwayID == "teal"); #expect(p.custom == nil)
    #expect(p.palette == Colorway.standard.palette)
}
@Test func persists() {
    let d = freshDefaults(); let p = AppearancePreferences(defaults: d)
    p.mode = .dark; p.choosePreset("ocean")
    let q = AppearancePreferences(defaults: d)
    #expect(q.mode == .dark); #expect(q.colorwayID == "ocean"); #expect(q.palette == Colorway.preset(id: "ocean")!.palette)
}
@Test func damagedValuesFallBack() {
    let d = freshDefaults()
    d.set(5, forKey: AppearancePreferences.modeKey); d.set(["x"], forKey: AppearancePreferences.colorwayKey)
    d.set("nope", forKey: AppearancePreferences.customKey); d.set(true, forKey: CalendarPreferences.showOnTimerPageKey)
    let p = AppearancePreferences(defaults: d)
    #expect(p.mode == .system); #expect(p.colorwayID == "teal"); #expect(p.custom == nil)
    #expect(d.bool(forKey: CalendarPreferences.showOnTimerPageKey)) // untouched
}
@Test func unknownColorwayLoadsAsTeal() {
    let d = freshDefaults(); d.set("neon", forKey: AppearancePreferences.colorwayKey)
    #expect(AppearancePreferences(defaults: d).colorwayID == "teal")
}
@Test func customWithDamagedColorsLoadsAsTeal() {
    let d = freshDefaults(); d.set("custom", forKey: AppearancePreferences.colorwayKey)
    d.set(["#336B82", "#6BB0C9", "#CC9433"], forKey: AppearancePreferences.customKey)
    let p = AppearancePreferences(defaults: d)
    #expect(p.colorwayID == "teal"); #expect(p.custom == nil)
}
@Test func customStartsFromThePickedPreset() {
    let p = AppearancePreferences(defaults: freshDefaults())
    p.choosePreset("sage"); p.chooseCustom()
    #expect(p.colorwayID == AppearancePreferences.customID); #expect(p.custom == Colorway.preset(id: "sage")!.palette)
}
@Test func customIsKeptAfterSwitchingAway() {
    let d = freshDefaults(); let p = AppearancePreferences(defaults: d)
    p.setCustom(RGBColor(hex: "#112233")!, for: .focusLight)
    #expect(p.colorwayID == AppearancePreferences.customID)
    p.choosePreset("ocean"); p.chooseCustom()
    #expect(p.palette.focusLight.hex == "#112233")
    #expect(AppearancePreferences(defaults: d).palette.focusLight.hex == "#112233")
}
@Test func unknownPresetIsIgnored() {
    let p = AppearancePreferences(defaults: freshDefaults()); p.choosePreset("plum"); p.choosePreset("neon")
    #expect(p.colorwayID == "plum")
}
```

- [ ] **Step 2: Run them and watch them fail.** Run: `swift test --filter AppearancePreferencesTests 2>&1 | tail -5`. Expected: a build failure, because `AppearancePreferences` doesn't exist.
- [ ] **Step 3: Implement `AppearancePreferences.swift`.** Follow `CalendarPreferences`: read each key with a type check and write it in `didSet` or the mutating methods.
- [ ] **Step 4: Run them and watch them pass.** Run: `swift test 2>&1 | tail -3`. Expected: 202 pass.
- [ ] **Step 5: Commit.** `git commit -m "feat: appearance preferences store"` (add both files).

### Task 3: The colourway applied everywhere, and the light/dark mode

**Files:**
- Modify: `Sources/FocusNow/Theme.swift`. Remove `focusNS`, `restNS`, `focus`, `onFocus`, `rest` and `color(for:)`; keep the motion values and `NSAppearance.isDark`.
- Modify: every current reader of those, namely `TimerParts.swift` (`TimerRing`, `TimerControlsRow`, `GoalBar`, `PressableButtonStyle`), `StatsView.swift:131,260`, `FocusCalendarView.swift` (blocks, block labels, today's date), `UpcomingEventsView.swift:74`, `SettingsView.swift:42` (sidebar icons) and `StatusItemController.swift:220-224`.
- Modify: `MainWindowView.swift`, `PopoverView.swift`, `AppDelegate.swift`, `StatusItemController.swift`, `SelfCheck.swift`.
- Create: `Sources/FocusNow/SelfCheckAppearance.swift`

**Interfaces:**
- Consumes: Task 2's `AppearancePreferences` and Task 1's `Palette` and `TextOnColor`.
- Produces (app target):
  - `extension EnvironmentValues { @Entry var palette: Palette = Colorway.standard.palette }`
  - `struct ThemeColors`, with:
    - `init(_ palette: Palette, dark: Bool)`;
    - `var focus: Color` and `var rest: Color`;
    - `func color(for kind: SessionKind) -> Color`;
    - `func text(on kind: SessionKind) -> Color`, white or #141414 by `TextOnColor`;
    - `var onFocus: Color`.
    
    Views build it from `@Environment(\.palette)` and `@Environment(\.colorScheme)`. They don't use dynamic `NSColor`s, so a subtree forced to light or dark (the Task 4 preview) gets that mode's colours.
  - `extension Color { init(_ rgb: RGBColor) }`
  - `PressableButtonStyle` gains `var text: Color = .white`, used for prominent labels.
  - `MainWindowView` and `PopoverView` take `appearance: AppearancePreferences` and apply `.environment(\.palette, appearance.palette)` at their root.
  - `StatusItemController(engine:palette:)` gains `palette: @escaping () -> Palette`.
    - The break tint is an `NSColor` built per draw from `palette().breakLight` and `breakDark`, with a dynamic provider on the button's appearance.
    - `redraw()` becomes internal.
    - `func setPopoverAppearance(_ appearance: NSAppearance?)` sets `popover.appearance`.
  - `AppDelegate`:
    - `private(set) var appearancePrefs: AppearancePreferences!`, built with `Self.defaults()`;
    - `private func followAppearance()`, a `withObservationTracking` loop like `reloadStatsWhenSettingsChange()` that reads `mode` and `palette`. On each change it sets `NSApp.appearance` (nil, `.aqua` or `.darkAqua`), calls `statusItem.setPopoverAppearance` with the same value, and calls `statusItem.redraw()`.
  - `SelfCheck`: a new `"appearance"` phase between `"calendar"` and `"timer"` in the default list, implemented as `checkAppearance(_:)` in `SelfCheckAppearance.swift`. The `persist` note adds `mode=… colorway=…`.

- [ ] **Step 1: Write the self-check phase first** (`checkAppearance`). It's the failing check for this task. It notes:
  - for each mode in system, light and dark: `mode=X app=<NSApp.effectiveAppearance name> window=<main window effectiveAppearance name> popover=<popover content view's effectiveAppearance name, shown via statusItem.showPopover(fromClick: true)> menubar=<status button effectiveAppearance name> (want window and popover follow X; menubar unchanged)`;
  - Stats set to the previous week (`statsModel` back one period), then `choosePreset("ocean")`: `stats period kept=<same interval before and after> (want true)`;
  - screenshots `timer-ocean` and `timer-ocean-dark` (window appearance forced, as `checkTimer` does), and `stats-ocean`;
  - a short break started (`engine.start()` twice, after completing focus via `nextFocusSecondsOverride = 2` and waiting, as other phases do), then `choosePreset("rose")`: `menubar break color=<hex of the title's foregroundColor resolved in the button's appearance> (want #3A9580 in light menubar, #7ACFB9 in dark)`.
  
  It ends with mode `.system`, preset `teal`, the break cancelled, and the popover closed.
- [ ] **Step 2: Run it and watch it fail.** Run: `scripts/self-check.sh appearance`. Expected: a build failure, because `appearancePrefs` doesn't exist.
- [ ] **Step 3: Implement the interfaces above.** Replace every listed `Theme.focus`, `Theme.rest`, `Theme.onFocus` and `Theme.restNS` use. Main buttons pass `text: colors.text(on: kind)`. Sidebar labels use `Label { Text(title) } icon: { Image(systemName:).foregroundStyle(colors.focus) }`.
- [ ] **Step 4: Run it and watch it pass.** Run: `swift build 2>&1 | grep -E "warning|error" ; scripts/self-check.sh appearance,stats,timer,calendar`. Expected:
  - no warnings;
  - every appearance line shows its want;
  - the existing stats, timer and calendar lines are unchanged;
  - read the `timer-ocean*` and `stats-ocean` shots: blue ring, blue buttons, coral nowhere in focus.
  
  Then `scripts/self-check.sh`. Expected: every phase matches its want.
- [ ] **Step 5: Commit.** `git commit -m "feat: colourway applied across the app, and light/dark mode"`

### Task 4: Settings → Appearance

**Files:**
- Create: `Sources/FocusNow/AppearanceSettingsPane.swift`, with `AppearancePane(preferences:)` and private views for the tiles, the colour wells and the preview.
- Modify: `SettingsView.swift`. Add `SettingsSection.appearance` last, titled "Appearance", with the symbol `paintpalette`. `SettingsView` takes `appearance: AppearancePreferences`.
- Modify: `MainWindowView.swift` (pass it through) and `SelfCheckAppearance.swift`.

**Interfaces:**
- Consumes: Tasks 2–3.
- Produces: the pane, laid out as in spec §3. Its parts:
  - **Mode:** a segmented `Picker` bound to `mode`.
  - **Tiles:** a 3-column `LazyVGrid` of 9 tiles, each a `Button`.
    - Each tile's `accessibilityLabel` is its name, with `.isSelected` added when chosen.
    - Presets call `choosePreset`. Custom calls `chooseCustom`.
    - A preset's circle shows its `focusLight` and `breakLight` halves. Custom's is a 4-colour conic gradient.
    - The chosen tile is outlined in `Color.accentColor`.
  - **Your colors:** shown only while `colorwayID == customID`. Four rows, one per `PaletteSlot` in order, each with:
    - a `ColorPicker("", selection:, supportsOpacity: false)` with labels hidden;
    - a numbered title and the description text from Global Constraints;
    - the note under the four rows.
    
    The binding converts with `NSColor(color).usingColorSpace(.sRGB)`. When that returns nil, it keeps the old colour.
  - **Preview:** two panels side by side, labelled "Light" and "Dark", each with `.environment(\.colorScheme, …)` and the current palette. Each panel draws:
    - the ring with "17:24";
    - a Start focus button;
    - − and +;
    - the goal bar;
    - 7 small bars;
    - a small break ring with a Start break button;
    - "Now" in the focus colour;
    - a menu-bar strip showing an hourglass and " 4:12" in the break colour on that mode's menu bar background.
    
    The preview reuses `TimerRing`'s look only through `ThemeColors`; it doesn't need a live engine.

- [ ] **Step 1: Extend `checkAppearance` first.** Show Settings → Appearance and note:
  - `tiles=<count of readable elements named like the 9 tiles> (want 9)` and `selected=<name of the tile with the selected trait> (want Teal & Amber)`;
  - after `snap.press(accessibilityLabel: "Sage & Clay")`: `colorway=<id> (want sage)`;
  - after pressing "Custom": `colorway=custom custom==sage=<bool> wells=<count of the four titles found with containsText> (want custom true 4)`;
  - `prefs.setCustom(#FF0000, .focusLight)`, then screenshots `appearance-custom` and `appearance-custom-dark`. Read them: red in the light preview, sage elsewhere.
  
  Leave `teal` chosen at the end.
- [ ] **Step 2: Run it and watch it fail.** Run: `scripts/self-check.sh appearance`. Expected: `tiles=0`, because there's no Appearance section.
- [ ] **Step 3: Implement the pane and the section.**
- [ ] **Step 4: Run it and watch it pass.** Run: `scripts/self-check.sh appearance,settings`. Expected:
  - every new line shows its want;
  - the settings phase is unchanged apart from the sidebar now listing 5 sections;
  - the shots match the approved mock (`.superpowers/brainstorm/20522-1795148634/content/appearance-settings.html`): tiles in 3 rows of 3, the wells with numbered text, and the two preview panels.
- [ ] **Step 5: Commit.** `git commit -m "feat: Settings → Appearance with presets and a custom colorway"`

### Task 5: Timer buttons in two rows

**Files:**
- Modify: `Sources/FocusNowCore/TimerControls.swift`, `Sources/FocusNow/TimerParts.swift` (`TimerControlsRow`), `Sources/FocusNow/TimerPageView.swift` (`TimerPageLayout.reserved`) and `SelfCheck.swift` (`checkTimer` and `checkPopover`).
- Test: `Tests/FocusNowCoreTests/TimerControlsTests.swift`

**Interfaces:**
- Produces:
  - `public struct ControlRows: Equatable, Sendable { public var main: TimerControl; public var others: [TimerControl] }`
  - `extension TimerEngine { public var controlRows: ControlRows }`. `main` is the first of `controls` that is `.startFocus`, `.startBreak`, `.pause` or `.resume`. `others` is the rest, in order.

- [ ] **Step 1: Write the failing test**

```swift
@Test func controlRowsForEveryState() {
    #expect(e.controlRows == ControlRows(main: .startFocus, others: [.adjustLength]))
    e.start(); #expect(e.controlRows == ControlRows(main: .pause, others: [.endEarly, .cancel]))
    e.pause(); #expect(e.controlRows == ControlRows(main: .resume, others: [.endEarly, .cancel]))
    e.resume(); h.run(2400); #expect(e.controlRows == ControlRows(main: .startBreak, others: [.skipBreak]))
    e.start(); #expect(e.controlRows == ControlRows(main: .pause, others: [.skip]))
    e.pause(); #expect(e.controlRows == ControlRows(main: .resume, others: [.skip]))
}
```

- [ ] **Step 2: Run it and watch it fail.** Run: `swift test --filter TimerControlsTests 2>&1 | tail -5`. Expected: a build failure, because `controlRows` doesn't exist.
- [ ] **Step 3: Implement `controlRows`.** Then rebuild `TimerControlsRow` as a `VStack(spacing: 6)`:
  - the main button, full width, prominent;
  - an `HStack(spacing: 6)` of the others, each full width.
  
  `.adjustLength` becomes two full-width buttons, − and +, in the plain non-compact style, keeping their accessibility labels. Raise `TimerPageLayout.reserved` by one button row plus 6 pt, measured from the self-check rather than guessed.
- [ ] **Step 4: Run it and watch it pass.** Run: `swift test 2>&1 | tail -3`, then `scripts/self-check.sh timer,popover`. In `checkTimer` and `checkPopover`, add a note per state (idle, running, paused, and a pending break in the popover) of the frames of the main button and the others:
  - `rows main=<title> w=<width> others=<titles> w=<widths> sameY=<bool> sum=<sum of other widths + 6×gaps> (want sum == main width, sameY true)`.
  
  Expected: the wants hold, and `ring idle == running` still holds at 760×560 and 640×480.
- [ ] **Step 5: Commit.** `git commit -m "feat: main timer action on its own row, the others beneath"`

### Task 6: Room around the ring at every size

**Files:**
- Modify: `Sources/FocusNow/TimerParts.swift`. In `TimerRing`, draw the track and the progress with `Circle().inset(by: lineWidth / 2)`. Give the ring's `ZStack` `.accessibilityElement(children: .contain)` and `.accessibilityIdentifier(TimerRing.ringIdentifier)`, where `static let ringIdentifier = "timer-ring"`.
- Modify: `Sources/FocusNow/TimerPageView.swift` (`TimerPageLayout` and the ring's padding) and `SelfCheck.swift` (`checkTimer`).

**Interfaces:**
- Produces: `TimerPageLayout.ringGap(for diameter: CGFloat) -> CGFloat = max(spacing, diameter * 0.12)`. The page pads the ring vertically by `ringGap − spacing` on each side. `rawDiameter` reserves that padding:

```swift
// avail = size.height - below (below as today). Padding starts once 0.12·d > 22, i.e. d > 183.3.
let fit = avail <= spacing / 0.12 ? avail : (avail + 2 * spacing) / 1.24
return min(min(size.width, size.height) * 0.7, fit)
```

- [ ] **Step 1: Write the failing self-check first.** In `checkTimer`, for each of 640×480, 760×560, 1400×900 and the main screen's `visibleFrame` size minus the title bar, each with events shown and hidden (`calendarPrefs.showOnTimerPage`; seed events with `seedCalendar()` from `SelfCheckCalendar.swift`), note:
  - `gaps WxH events=on|off: above=<phase label frame minY − ring frame maxY> below=<ring minY − main button maxY> ring=<ring height> fits=<lowest readable element's minY ≥ content view's screen minY> (want ≥22 ≥22 ≥120 true)`.
  
  Restore 760×560 with events shown.
- [ ] **Step 2: Run it and watch it fail.** Run: `scripts/self-check.sh timer`. Expected: `ring=-1` (no identifier yet), and at 1400×900 a `below` under 22.
- [ ] **Step 3: Implement the stroke inset, the identifier, `ringGap` and the new `rawDiameter`.**
- [ ] **Step 4: Run it and watch it pass.** Run: `scripts/self-check.sh timer,calendar,popover`. Expected:
  - every `gaps` line meets its want;
  - the VoiceOver lines in `checkTimer` read as before (digits, then controls);
  - the popover ring still shows 150 pt with its digits inside;
  - the `timer-running-large` shot shows clear space below the ring.
- [ ] **Step 5: Commit.** `git commit -m "fix: keep the ring clear of the buttons at every window size"`

### Task 7: A set focus length stays

**Files:**
- Modify: `Sources/FocusNowCore/Model.swift` (`EngineSnapshot`), `Sources/FocusNowCore/TimerEngine.swift` and `Sources/FocusNowCore/TimerControls.swift` (doc comments: "one-off" becomes "set length").
- Test: create `Tests/FocusNowCoreTests/TimerEngineFocusLengthTests.swift`, and delete `oneOffLengthAppliesOnceOnly` from `TimerEngineTests.swift`, since the new behaviour replaces it.

**Interfaces:**
- Produces:
  - `public struct FocusOverride: Codable, Equatable, Sendable { public var seconds: Int; public var focusMinutes: Int }`. It replaces the engine's private `OneOff`.
  - `EngineSnapshot` gains `public var focusOverride: FocusOverride?`, and `init` gains a trailing `focusOverride: FocusOverride? = nil`. Snapshots saved without it decode as nil.
  - `TimerEngine`:
    - `start()` no longer clears the override;
    - `setNextFocus`, `focusDefaultChanged()` and the tick that drops a stale override all save a snapshot;
    - `recover(from:)` restores the override;
    - the public `nextFocusSecondsOverride` keeps its name and meaning.

- [ ] **Step 1: Write the failing tests** (Harness as in `TimerControlsTests`; the default Focus is 40 min)

```swift
@Test func staysAfterStartAndCancel() {
    e.setNextFocus(minutes: 25); e.start(); #expect(e.active?.plannedSeconds == 1500)
    e.cancel(); #expect(e.remainingSeconds == 1500)
}
@Test func staysThroughFinishAndBreak() {
    e.setNextFocus(minutes: 25); e.start(); h.run(1500)
    #expect(e.remainingSeconds == 300); e.start(); h.run(300)
    #expect(e.nextKind == .focus); #expect(e.remainingSeconds == 1500)
}
@Test func staysAfterEndEarly() {
    e.setNextFocus(minutes: 25); e.start(); h.run(120); e.endEarly(); e.skipBreak()
    #expect(e.remainingSeconds == 1500)
}
@Test func staysOnANewDay() {
    e.setNextFocus(minutes: 25); h.clock.advance(86_400); e.tick(); #expect(e.remainingSeconds == 1500)
}
@Test func survivesRelaunch() {
    e.setNextFocus(minutes: 25); h.relaunch(); #expect(h.engine.remainingSeconds == 1500)
}
@Test func relaunchWithAChangedFocusDefaultDropsTheLength() {
    e.setNextFocus(minutes: 25); h.settings.value.focusMinutes = 30; h.relaunch()
    #expect(h.engine.remainingSeconds == 1800); #expect(h.engine.nextFocusSecondsOverride == nil)
}
@Test func settingAgainReplacesIt() {
    e.setNextFocus(minutes: 25); e.start(); e.cancel(); e.adjustNextFocus(byMinutes: 5)
    #expect(e.remainingSeconds == 1800)
}
@Test func snapshotWithoutALengthDecodes() throws {
    // The five keys an older build wrote, with FileSnapshotStore's own decoder settings.
    let old = try encodedOldSnapshot()   // helper: encode EngineSnapshot(focusOverride: nil) and check the key is absent
    #expect(try decodeSnapshot(old).focusOverride == nil)
}
```

  For the last test, read `FileSnapshotStore.swift` for its encoder and decoder settings, and put the two small helpers in the test file.
- [ ] **Step 2: Run them and watch them fail.** Run: `swift test --filter TimerEngineFocusLengthTests 2>&1 | tail -5`. Expected: a build failure, because `focusOverride` doesn't exist. Once that compiles, `staysAfterStartAndCancel` fails with 2400.
- [ ] **Step 3: Implement it.** Then fix the self-check, which relies on the old behaviour:
  - Every `engine.nextFocusSecondsOverride = N` in `SelfCheck*.swift` sets a short length so a session finishes quickly; today it vanishes when that session starts. Find them with `grep -n "nextFocusSecondsOverride =" Sources/FocusNow/SelfCheck*.swift`. Today that's lines 187, 595 and 681, plus Task 3's appearance phase. Reset each to nil right after the quick session starts. Otherwise every later phase runs 2-second sessions.
  - Reread the `digits` and `commits` phases (`SelfCheck.swift` near lines 466–606). Update any "want" that assumes the length resets after a session starts, and add a note there: `after cancel remaining=<clock> (want the typed length)`. End each of those phases with the length cleared (`engine.focusDefaultChanged()`).
- [ ] **Step 4: Run them and watch them pass.** Run: `swift test 2>&1 | tail -3`. Expected: all pass (202 − 1 + 1 from Task 5 + 8 = 210). Then `scripts/self-check.sh`. Expected: every phase matches its want, and no phase after `digits` runs a session shorter than its default length (check the logged `remaining=` values).
- [ ] **Step 5: Commit.** `git commit -m "feat: a focus length set on the timer stays until changed"`

### Task 8: Cycle units against the steppers

**Files:**
- Modify: `Sources/FocusNow/LengthField.swift`. The unit `Text` frame changes from `alignment: .leading` to `.trailing`, and the doc comment updates to match.

- [ ] **Step 1: Look at the current shot.** Run: `scripts/self-check.sh settings`, then read `build/selfcheck.noindex/shots/` for the Cycle section shot. "min" sits left in its column, with a gap before the stepper.
- [ ] **Step 2: Change the alignment.**
- [ ] **Step 3: Run it again and read the shot.** Run: `scripts/self-check.sh settings`. Expected:
  - "min" and "sessions" end at the same x, just left of their steppers;
  - the number fields are unchanged;
  - the Goal row (no unit) is unchanged;
  - the settings lines are unchanged.
- [ ] **Step 4: Commit.** `git commit -m "fix: Cycle units sit next to their steppers"`

### Task 9: Event times as a range

**Files:**
- Create: `Sources/FocusNowCore/EventTimeText.swift`
- Test: `Tests/FocusNowCoreTests/EventTimeTextTests.swift`
- Modify: `Sources/FocusNow/UpcomingEventsView.swift` (`EventRow`) and `Sources/FocusNow/SelfCheckCalendar.swift` (the row expectation).

**Interfaces:**
- Produces: `public enum EventTimeText`, with:
  - `static func range(_ event: CalendarEvent, calendar: Calendar, locale: Locale) -> String`. It uses a `DateIntervalFormatter` with date style none and time style short, in the calendar's time zone. If a range across midnight comes out with dates, it falls back to the two short times joined by "–".
  - `static func spoken(_ event: CalendarEvent, calendar: Calendar, locale: Locale) -> String`, as "1:30 PM to 3:47 PM".

- [ ] **Step 1: Write the failing tests** (UTC calendar; `event(...)` from `TestSupport.swift`)

```swift
let us = Locale(identifier: "en_US"), gb = Locale(identifier: "en_GB")
@Test func afternoonRangeSharesPM() {
    let t = EventTimeText.range(event(start: "2026-11-19T13:30:00Z", end: "2026-11-19T15:47:00Z"), calendar: utc, locale: us)
    #expect(t.contains("1:30")); #expect(t.contains("3:47 PM")); #expect(t.components(separatedBy: "PM").count == 2)
}
@Test func rangeAcrossNoon() {
    let t = EventTimeText.range(event(start: "2026-11-19T11:30:00Z", end: "2026-11-19T12:15:00Z"), calendar: utc, locale: us)
    #expect(t.contains("11:30 AM")); #expect(t.contains("12:15 PM"))
}
@Test func twentyFourHour() {
    let t = EventTimeText.range(event(start: "2026-11-19T13:30:00Z", end: "2026-11-19T15:47:00Z"), calendar: utc, locale: gb)
    #expect(t.contains("13:30")); #expect(t.contains("15:47"))
}
@Test func overnightShowsTimesOnly() {
    let t = EventTimeText.range(event(start: "2026-11-18T23:00:00Z", end: "2026-11-19T01:00:00Z"), calendar: utc, locale: us)
    #expect(t.contains("11:00 PM")); #expect(t.contains("1:00 AM")); #expect(!t.contains("Nov")); #expect(!t.contains("18"))
}
@Test func spokenRange() {
    #expect(EventTimeText.spoken(event(start: "2026-11-19T13:30:00Z", end: "2026-11-19T15:47:00Z"), calendar: utc, locale: us)
            == "1:30 PM to 3:47 PM")
}
```

  Match the `event(...)` helper's real parameter labels in `TestSupport.swift`.
- [ ] **Step 2: Run them and watch them fail.** Run: `swift test --filter EventTimeTextTests 2>&1 | tail -5`. Expected: a build failure, because `EventTimeText` doesn't exist.
- [ ] **Step 3: Implement `EventTimeText`, then update `EventRow`:**
  - dot;
  - the range: secondary, monospaced digits, one line, in a fixed 118 pt leading column with `minimumScaleFactor(0.85)`;
  - the title, truncated in the middle;
  - a spacer;
  - "Now" when `isNow`: semibold, in the focus colour.
  
  The accessibility label is `"\(spoken), \(title)" + (isNow ? ", now" : "")`. Use `Calendar.autoupdatingCurrent` and `Locale.autoupdatingCurrent`. In `SelfCheckCalendar.swift`, change the want to `"<spoken>, Standup, now"`.
- [ ] **Step 4: Run them and watch them pass.** Run: `swift test 2>&1 | tail -3` (215 pass), then `scripts/self-check.sh calendar,timer`. Expected:
  - the first row reads "… to …, Standup, now";
  - the row heights are unchanged;
  - the long-title row is still one line at 640×480;
  - the `timer-events` shots show the ranges in a column, with "Now" at the right.
- [ ] **Step 5: Commit.** `git commit -m "feat: calendar rows show their start and end time"`

### Task 10: The app icon from icon.svg

**Files:**
- Copy: `icon.svg` → `Resources/Icon/icon.svg` and `icon.png` → `Resources/Icon/icon.png` (`cp`; the originals stay).
- Modify: `.gitignore` (add `icon.svg` and `Resources/Icon/` under "Kept on this Mac only"), `scripts/make-icon.swift` and `scripts/build-app.sh:11-13`.

**Interfaces:**
- Produces: `swift scripts/make-icon.swift [source.svg] [output-dir]`, defaulting to `Resources/Icon/icon.svg` and `build`.
  - It loads the SVG with `NSImage(contentsOf:)` and fails clearly if that's nil.
  - For each iconset size, it draws the image into the 824-pt square at (100, 100) of a 1024 canvas, with a shadow (offset 0, −10; blur 20; black at 0.3) set while drawing, so the shadow follows the icon's own outline.
  - It writes the same iconset and `.icns` as today. The crop constants go.
  - `build-app.sh` rebuilds the icon when `Resources/Icon/icon.svg` or the script is newer than `build/AppIcon.icns`.

- [ ] **Step 1: Copy the files and update `.gitignore`.** Run: `git status --short`. Expected: neither `icon.svg` nor `Resources/Icon/` is listed; only `.gitignore` shows as modified.
- [ ] **Step 2: Rewrite `make-icon.swift` and update `build-app.sh`.**
- [ ] **Step 3: Run it and look.** Run: `rm -f build/AppIcon.icns && scripts/build-app.sh`. Expected: `wrote build/AppIcon.icns`, then a signed line. Read `build/AppIcon.iconset/icon_512x512@2x.png` and `icon_16x16@2x.png`: the hourglass tile, centred, with a soft shadow, transparent corners and no cropping. Then run `scripts/self-check.sh timer`. Expected: the launch line has `iconFile=true`.
- [ ] **Step 4: Commit.** `git add .gitignore scripts/make-icon.swift scripts/build-app.sh && git commit -m "feat: build the app icon from icon.svg"`. Check `git show --stat HEAD` lists no icon files.

### Finish

- [ ] **Run everything.** Run: `swift test 2>&1 | tail -3`. Expected: all pass. Then `scripts/self-check.sh`. Expected: every phase matches its want.
- [ ] **Owner's hand checks:** the real colour panel; each mode against the real menu bar; the new icon in the Dock and Finder after `scripts/build-app.sh --install`, which the owner runs.
