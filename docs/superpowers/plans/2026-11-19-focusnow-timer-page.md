# FocusNow Timer Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app window opens on a Timer page (timer plus cycle configuration, which hides once a session starts) with Stats as a second page, and every length can be typed.

**Architecture:**
- Parsing typed text and the engine rules (typed one-off length, the −/+ range, the one-off dropping when the Focus default changes, "in a session") go in `FocusNowCore`, test-first with Swift Testing.
- The app target gets shared timer view parts, a reusable `LengthField`, a `TimerPageView` and a `MainWindowView` with a toolbar switch. One main window replaces the stats window.
- App behaviour is verified by the in-process self-check, run through a new `scripts/self-check.sh`.

**Tech Stack:** Swift 6, SwiftUI hosted in AppKit, Swift Testing. Apple frameworks only.

**Spec:** `docs/superpowers/specs/2026-11-19-focusnow-timer-page-design.md`. It builds on `docs/superpowers/specs/2026-11-19-focusnow-v1-design.md`, which still binds where the new spec is silent.

## Global Constraints

- **Platform:** Apple frameworks only. Minimum macOS 14, so no macOS 15-only API (for example `TabView`'s `.sidebarAdaptable` or `.pointerStyle`).
- **Colours:** live only in `Sources/FocusNow/Theme.swift`.
- **Countdown digits:** use tabular digits and never animate (`.contentTransition(.identity)`).
- **Typed values:**
  - Lengths are whole minutes, 1–180. "Long break after" is 1–12 sessions. The goal is 15 min–16 h (`TimerSettings.goalRange`).
  - A value commits on Return or when the field loses focus; Escape reverts. Out-of-range values clamp; unparseable text reverts.
- **Motion:**
  - Hiding or showing the configuration takes 0.3 s with `.timingCurve(0.77, 0, 0.175, 1)`. The configuration fades and shifts 12 pt right.
  - With Reduce Motion it only fades, and the ring takes its new size without animating.
  - Switching pages is not animated.
- **Testing:** test each step before the next. Every app task ends with a self-check run whose log you read. The self-check only ever runs against `FOCUSNOW_DATA_DIR`, never real data.
- **Your running copy:** never quit the owner's running `/Applications/FocusNow.app` without asking.
- **Commits:** commit at the end of every task, ending the message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Editing when something else changes the state:** a session starts from the popover, or the countdown finishes, while a config field or the digits are being edited on the Timer page. Editing ends cleanly. The digits drop the edit; a config field commits what it had. Nothing crashes. Checked in Task 5's self-check.
2. **Window extremes:**
   - At the minimum size (640×480), the idle two-column layout doesn't clip the configuration column.
   - When large, the ring scales up, and "3:00:00" never truncates in the ring or the popover.

   Checked in Tasks 4 and 5.
3. **Typing in the popover:** keystrokes reach the field. Leaving the popover mid-edit commits the typed value rather than losing it. Checked in Task 5. Real keystrokes while another app is frontmost go on the owner's hand-check list.
4. **One timer, two surfaces:** starting, pausing or cancelling from the popover while the Timer page is open switches the page between its idle and session layouts. Checked in Task 4 (the self-check drives the shared engine as the popover does).
5. **Typed text people actually enter:** "25:00", "1:30", "2.5", "-5", "" and "4 sessions" in the wrong field. Each parses as the spec says or reverts. Unit tests in Task 1.

---

## File Structure

```
Sources/FocusNowCore/
  LengthInput.swift        new: parse typed minutes, sessions and goals
  TimerEngine.swift        one-off length remembers the Focus default it was set against
  TimerControls.swift      setNextFocus(minutes:), −/+ range 1–180, isInSession
Sources/FocusNow/
  TimerParts.swift         new: TimerRing, TimerControlsRow, TodayBar, button styles, GoalBar (moved out of PopoverView)
  LengthField.swift        new: text field + unit + stepper, commit/revert rules
  TimerPageView.swift      new: idle two-column layout / full-window session layout
  MainWindowView.swift     new: MainPage, MainWindowState, toolbar Timer | Stats
  PopoverView.swift        uses TimerParts; digits typeable (Task 5)
  SettingsView.swift       Timer section removed; goal typeable
  WindowCoordinator.swift  one main window replaces the stats window
  AppDelegate.swift        showTimer/showStats pick the page; Window menu Timer ⌘1, Stats ⌘2
  DebugSnapshots.swift     typing, key and press helpers for the self-check
  SelfCheck.swift          phases updated; new phases timer and digits
scripts/self-check.sh      new: build and run the self-check against a scratch folder
Tests/FocusNowCoreTests/
  LengthInputTests.swift   new
  TimerControlsTests.swift extended
```

---

### Task 1: Parsing typed lengths

**Files:**
- Create: `Sources/FocusNowCore/LengthInput.swift`
- Test: `Tests/FocusNowCoreTests/LengthInputTests.swift`

**Interfaces:**
- Consumes: `TimerSettings.minuteRange` (1...180), `TimerSettings.sessionsRange` (1...12), `TimerSettings.goalRange` (900...57_600).
- Produces:
  ```swift
  public enum LengthInput {
      /// "25", "25m", "25 min", "25 minutes", "1 minute" → clamped to range; nil otherwise.
      public static func minutes(_ text: String, in range: ClosedRange<Int>) -> Int?
      /// "4", "4 sessions", "1 session" → clamped to range; nil otherwise.
      public static func sessions(_ text: String, in range: ClosedRange<Int>) -> Int?
      /// "4h", "4", "3h 30m", "3h30m", "3:30", "90m", "90 min", "1.5h", "1.5" → seconds,
      /// rounded to the minute and clamped to TimerSettings.goalRange; nil otherwise.
      public static func goalSeconds(_ text: String) -> Int?
  }
  ```

- [ ] **Step 1: Write the failing tests** in `LengthInputTests.swift`:

```swift
@Test func minutesAcceptsNumbersWithOrWithoutAUnit() {
    for text in ["25", " 25 ", "25m", "25 m", "25min", "25 min", "25 Minutes", "25 mins"] {
        #expect(LengthInput.minutes(text, in: 1...180) == 25, "\(text)")
    }
    #expect(LengthInput.minutes("1 minute", in: 1...180) == 1)
}
@Test func minutesClampToTheRange() {
    #expect(LengthInput.minutes("0", in: 1...180) == 1)
    #expect(LengthInput.minutes("999", in: 1...180) == 180)
}
@Test func minutesRejectEverythingElse() {
    for text in ["", "  ", "abc", "-5", "2.5", "25:00", "1:30", "25h", "m"] {
        #expect(LengthInput.minutes(text, in: 1...180) == nil, "\(text)")
    }
}
@Test func sessionsAcceptCountsWithOrWithoutAUnit() {
    #expect(LengthInput.sessions("4", in: 1...12) == 4)
    #expect(LengthInput.sessions("4 sessions", in: 1...12) == 4)
    #expect(LengthInput.sessions("1 session", in: 1...12) == 1)
    #expect(LengthInput.sessions("0", in: 1...12) == 1)
    #expect(LengthInput.sessions("99", in: 1...12) == 12)
    #expect(LengthInput.sessions("4 min", in: 1...12) == nil)
    #expect(LengthInput.sessions("x", in: 1...12) == nil)
}
@Test func goalAcceptsHoursAndMinutesInCommonForms() {
    let cases: [(String, Int)] = [
        ("4h", 14_400), ("4", 14_400), ("4 h", 14_400), ("3h 30m", 12_600), ("3h30m", 12_600),
        ("3:30", 12_600), ("0:45", 2_700), ("90m", 5_400), ("90 min", 5_400),
        ("1.5h", 5_400), ("1.5", 5_400), ("2H 15M", 8_100),
    ]
    for (text, seconds) in cases { #expect(LengthInput.goalSeconds(text) == seconds, "\(text)") }
}
@Test func goalClampsToFifteenMinutesThroughSixteenHours() {
    #expect(LengthInput.goalSeconds("5m") == 900)
    #expect(LengthInput.goalSeconds("20h") == 57_600)
}
@Test func goalRejectsEverythingElse() {
    for text in ["", "abc", "h", "3:75", "-2h", "4 sessions", "3:"] {
        #expect(LengthInput.goalSeconds(text) == nil, "\(text)")
    }
}
```

- [ ] **Step 2: Run** `swift test --filter LengthInputTests 2>&1 | tail -5`. Expected: build fails, "cannot find 'LengthInput' in scope".

- [ ] **Step 3: Implement `LengthInput`** in `LengthInput.swift`. Trim and lowercase the text, then match whole-string Swift `Regex`es:
  - **Minutes:** `^(\d+)\s*(m|min|mins|minute|minutes)?$`.
  - **Sessions:** `^(\d+)\s*(session|sessions)?$`.
  - **Goal,** in this order: `H:MM` (MM 00–59); `Nh Mm` with an optional space; `N(.N)? h`; `N m|min`; bare `N(.N)?` as hours.

  Clamp with the existing `Comparable.clamped(to:)`.

- [ ] **Step 4: Run** `swift test 2>&1 | tail -3`. Expected: all tests pass (123 earlier + 7 new).

- [ ] **Step 5: Commit:** `git add Sources/FocusNowCore/LengthInput.swift Tests/FocusNowCoreTests/LengthInputTests.swift && git commit -m "feat: parse typed lengths, session counts and goals"`.

---

### Task 2: Engine rules for typed and one-off lengths

**Files:**
- Modify: `Sources/FocusNowCore/TimerEngine.swift` (the `nextFocusSecondsOverride` property, `tick()`)
- Modify: `Sources/FocusNowCore/TimerControls.swift`
- Test: `Tests/FocusNowCoreTests/TimerControlsTests.swift`

**Interfaces:**
- Consumes: `TimerSettings.minuteRange`.
- Produces:
  ```swift
  extension TimerEngine {
      public static let adjustRangeMinutes: ClosedRange<Int>   // now 1...180 (TimerSettings.minuteRange)
      /// Sets only the next focus session's length; whole minutes, clamped to 1–180.
      /// Does nothing unless idle with a focus session next.
      public func setNextFocus(minutes: Int)
      /// True while a session is running or paused (the Timer page hides its configuration).
      public var isInSession: Bool
  }
  // TimerEngine.nextFocusSecondsOverride stays `public var Int?` for callers, but a value
  // set against one Focus default reads as nil once the Focus default changes, and tick()
  // clears it for good, so changing the default back never brings it back.
  ```

- [ ] **Step 1: Write the failing tests.**

  Replace `adjustingIsClampedToFiveThroughOneEighty` with the first test below, then add the rest to `TimerControlsTests.swift`:

```swift
@Test func adjustingIsClampedToOneThroughOneEighty() {
    e.setNextFocus(minutes: 3)
    e.adjustNextFocus(byMinutes: -5)
    #expect(e.remainingSeconds == 60)
    for _ in 0..<50 { e.adjustNextFocus(byMinutes: 5) }
    #expect(e.remainingSeconds == 10_800)
}
@Test func typingTheNextFocusLengthSetsOnlyTheNextSession() {
    e.setNextFocus(minutes: 25)
    #expect(e.remainingSeconds == 1500)
    #expect(h.settings.value.focusMinutes == 40)
    e.start()
    #expect(e.active?.plannedSeconds == 1500)
}
@Test func typedLengthIsClamped() {
    e.setNextFocus(minutes: 0)
    #expect(e.remainingSeconds == 60)
    e.setNextFocus(minutes: 999)
    #expect(e.remainingSeconds == 10_800)
}
@Test func typingOnlyAppliesBeforeAFocusSession() {
    e.start()
    e.setNextFocus(minutes: 25)
    #expect(e.nextFocusSecondsOverride == nil)
    h.run(2400) // short break pending
    e.setNextFocus(minutes: 25)
    #expect(e.nextFocusSecondsOverride == nil)
    #expect(e.remainingSeconds == 300)
}
@Test func changingTheFocusDefaultDropsTheOneOff() {
    e.adjustNextFocus(byMinutes: 5)
    h.settings.value.focusMinutes = 30
    #expect(e.remainingSeconds == 1800)
    #expect(e.nextFocusSecondsOverride == nil)
    e.tick()
    h.settings.value.focusMinutes = 40
    #expect(e.remainingSeconds == 2400)
}
@Test func otherSettingsChangesKeepTheOneOff() {
    e.adjustNextFocus(byMinutes: 5)
    h.settings.value.shortBreakMinutes = 7
    h.settings.value.dailyGoalSeconds = 3600
    #expect(e.remainingSeconds == 2700)
}
@Test func inASessionWhileRunningOrPausedOnly() {
    #expect(!e.isInSession)
    e.start(); #expect(e.isInSession)
    e.pause(); #expect(e.isInSession)
    e.resume(); h.run(2400)
    #expect(!e.isInSession) // break pending
    e.start(); #expect(e.isInSession)
    e.skipBreak(); #expect(!e.isInSession)
}
```

- [ ] **Step 2: Run** `swift test --filter TimerControlsTests 2>&1 | tail -15`. Expected: build fails on `setNextFocus` and `isInSession`.

- [ ] **Step 3: Implement.**
  - **In `TimerEngine.swift`:**
    - Back `nextFocusSecondsOverride` with a private stored `oneOff: (seconds: Int, focusMinutes: Int)?`. Use a small private struct so it stays observable.
    - The public getter returns `seconds` only while `settings().focusMinutes == oneOff.focusMinutes`. The setter records the current `focusMinutes`.
    - `tick()` sets `oneOff = nil` when it no longer matches, before its idle early-return.
    - `start()` keeps clearing it.
  - **In `TimerControls.swift`:**
    - `adjustRangeMinutes = TimerSettings.minuteRange`.
    - `setNextFocus(minutes:)` uses the same guard as `adjustNextFocus`.
    - `isInSession` is `status != .idle`.

- [ ] **Step 4: Run** `swift test 2>&1 | tail -3`. Expected: all pass. The existing `oneOffLengthNeverAppliesToBreaks` still passes unchanged.

- [ ] **Step 5: Commit:** `git commit -am "feat: typed one-off length, 1–180 adjust range, one-off follows the focus default"`.

---

### Task 3: Shared timer parts, `LengthField`, Settings, self-check runner

**Files:**
- Create: `Sources/FocusNow/TimerParts.swift`, `Sources/FocusNow/LengthField.swift`, `scripts/self-check.sh`
- Modify: `Sources/FocusNow/PopoverView.swift`, `Sources/FocusNow/SettingsView.swift`, `Sources/FocusNow/DebugSnapshots.swift`, `Sources/FocusNow/SelfCheck.swift`

**Interfaces:**
- Consumes: `LengthInput.goalSeconds`, `TimeFormat.duration`, `TimerEngine.controls`, `TimerEngine.adjustNextFocus(byMinutes:)`.
- Produces:
  ```swift
  struct TimerRing: View { init(engine: TimerEngine, diameter: CGFloat) }      // stroke = diameter*8/150, digits = diameter*34/150, light weight
  struct TimerControlsRow: View { init(engine: TimerEngine, onAction: @escaping (TimerControl) -> Void) }
  struct TodayBar: View { init(engine: TimerEngine, settings: SettingsStore) }
  // PressableButtonStyle, FooterButtonStyle, GoalBar move here unchanged.
  struct LengthField: View {
      init(value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String?,
           parse: @escaping (String) -> Int?, format: @escaping (Int) -> String)
  }
  // DebugSnapshots:
  func textFields(in window: NSWindow) -> [NSTextField]                 // editable, in view order
  func type(_ text: String, intoField index: Int, of window: NSWindow) async  // select all, type, no Return
  func pressKey(_ keyCode: UInt16, characters: String, in window: NSWindow) async // 36 = Return, 53 = Escape
  ```
  `scripts/self-check.sh [phases]` builds the app and runs it against `build/selfcheck.noindex/{data,shots}`. It prints `shots/log.txt`.

- [ ] **Step 1: Baseline.**
  - Write `scripts/self-check.sh` (make it executable). It should:
    1. Run `scripts/build-app.sh`.
    2. Stop only stale development copies: `pkill -f "Release.noindex/FocusNow.app" || true`. Never touch `/Applications`.
    3. Recreate `build/selfcheck.noindex/{data,shots}`.
    4. Run `defaults delete local.focusnow.app.testing`, ignoring a failure.
    5. Launch the binary with `FOCUSNOW_SNAPSHOT_DIR`, `FOCUSNOW_DATA_DIR` and `FOCUSNOW_SELFCHECK`.
    6. In the background, wait for `shots/ready-for-reopen` and then run `open "$APP"`.
    7. Wait for the binary to exit and `cat shots/log.txt`.
  - Run `scripts/self-check.sh popover && cp -R build/selfcheck.noindex/shots build/selfcheck-baseline.noindex`. Expected: the log ends with "quitting with a running session". `popover-idle.png` and the other renders exist.

- [ ] **Step 2: Move the popover's parts into `TimerParts.swift`.**
  - `PopoverView` keeps only layout: phase label, `TimerRing(diameter: 150)`, `TimerControlsRow`, `TodayBar`, `Divider`, footer.
  - Move the phase crossfade and ring transition with the parts unchanged.

- [ ] **Step 3: Write `LengthField`.**
  - A right-aligned `TextField` about 52 pt wide with monospaced digits, the unit label, then a `Stepper` on the same binding (`range`, `step`).
  - The field edits a local `@State text`. On `.onSubmit`, or when its `@FocusState` turns false, it applies `parse`:
    - a non-nil result sets the binding;
    - either way, the text then shows `format(binding)`.
  - `.onExitCommand` restores `format(binding)` and drops focus.
  - When the binding changes while the field isn't focused (stepper or elsewhere), the text follows.

- [ ] **Step 4: Settings.**
  - Delete the Timer section.
  - The goal row becomes `LengthField(value: $settings.settings.dailyGoalSeconds, range: TimerSettings.goalRange, step: 900, unit: nil, parse: LengthInput.goalSeconds, format: TimeFormat.duration)` beside its "Daily focus goal" label.

- [ ] **Step 5: Self-check.**
  - Add the three `DebugSnapshots` helpers:
    - `type` makes the field first responder, sends `selectAll:`, then one synthesized `keyDown`/`keyUp` per character through `window.sendEvent`.
    - `pressKey` sends a single key.
  - In `checkSettings`, replace the focus-minutes lines with goal typing on the Settings window (`NSApp.windows.first { $0.title == "Settings" }`):
    - type "3h 30m" + Return, and note `typed 3h 30m → <TimeFormat.duration(goal)>`;
    - type "abc" + Return, and note `typed abc → …`;
    - type "5h" + Escape, and note `escape → …`;
    - type "2h" then make the window's first responder nil, and note `left field → …`;
    - set the goal back to 3 h.
  - Note `fields=\(textFields(in:).count)`.

- [ ] **Step 6: Run** `swift test 2>&1 | tail -3 && scripts/self-check.sh settings,popover`. Expected:
  - The tests pass.
  - The log shows `fields=1`, `typed 3h 30m → 3h 30m`, `typed abc → 3h 30m`, `escape → 3h 30m` and `left field → 2h`.
  - The popover lines match the baseline log: the same controls, remaining, flash and frontmost lines.
  - Read `popover-idle.png` and `popover-focus-running.png` against the baseline copies; they look the same.
  - Read `settings-live.png`: Goal and General only.

  If synthesized typing never reaches the field (the values don't change), rule on it in the ledger. Verify the parse path by setting the field's text through its binding, and add "typing in Settings" to the hand-check list.

- [ ] **Step 7: Commit** all files from this task: `git commit -m "feat: shared timer parts, typeable goal, self-check runner"`.

---

### Task 4: Main window with Timer and Stats pages

**Files:**
- Create: `Sources/FocusNow/MainWindowView.swift`, `Sources/FocusNow/TimerPageView.swift`
- Modify: `Sources/FocusNow/WindowCoordinator.swift`, `Sources/FocusNow/AppDelegate.swift`, `Sources/FocusNow/SelfCheck.swift`

**Interfaces:**
- Consumes: `TimerRing`, `TimerControlsRow`, `TodayBar`, `LengthField` (Task 3); `TimerEngine.isInSession` (Task 2); `LengthInput.minutes` / `.sessions` (Task 1).
- Produces:
  ```swift
  enum MainPage: Hashable { case timer, stats }
  @MainActor @Observable final class MainWindowState { var page: MainPage = .timer }
  struct MainWindowView: View { init(state: MainWindowState, engine: TimerEngine, settings: SettingsStore,
                                      statsModel: StatsViewModel, onAction: @escaping (TimerControl) -> Void) }
  struct TimerPageView: View { init(engine: TimerEngine, settings: SettingsStore, onAction: @escaping (TimerControl) -> Void) }
  // WindowCoordinator: init(makeMain:makeSettings:), showMain(), isMainVisible, mainWindow (title "FocusNow")
  // AppDelegate: showTimer(), showStats() set mainState.page then show the main window
  ```

- [ ] **Step 1: `TimerPageView`.**
  - Inside a `GeometryReader`, with `inSession = engine.isInSession`.
  - **Idle:** an `HStack(spacing: 0)` holding:
    - the timer column (`width * 0.62`): phase label, `TimerRing(diameter: min(columnWidth * 0.6, height - 190))`, `TimerControlsRow`, and `TodayBar` capped at 320 pt wide;
    - a `Divider`;
    - the configuration column (`width * 0.38`), with rows Focus, Short break and Long break (`LengthField`, unit "min", step 1, `LengthInput.minutes(_, in: TimerSettings.minuteRange)`, format `"\($0)"`) and Long break after (unit "sessions", `LengthInput.sessions`).

      Use a grouped `Form` if it fits at 640 pt wide, otherwise a `Grid`.
  - **In session:** the configuration is removed; the ring diameter is `min(min(width, height) * 0.7, height - 170)`.
  - Apply motion per Global Constraints, keyed on `inSession`. The configuration's transition is `.opacity.combined(with: .offset(x: 12))`, or `.opacity` under Reduce Motion.

- [ ] **Step 2: `MainWindowView` and window wiring.**
  - The content switches on `state.page` with no animation.
  - Add `.toolbar { ToolbarItem(placement: .principal) { Picker } }`, a segmented Timer | Stats picker bound to `state.page`.
  - **WindowCoordinator:**
    - The stats window becomes the main window: title "FocusNow" with `titleVisibility = .hidden`, the same size, minimum and resizability, and autosave name "FocusNowMainWindow".
    - Set `NSHostingController.sceneBridgingOptions = [.toolbars]` so the SwiftUI toolbar reaches the `NSWindow`. If the toolbar doesn't appear, rule on it and put the picker at the top of the content instead.
  - **AppDelegate:**
    - Add `mainState`.
    - A launch that isn't a login item, `applicationShouldHandleReopen`, and Window ▸ Timer (⌘1) call `showTimer()`.
    - Window ▸ Stats (⌘2) and the popover's Stats button call `showStats()`.
    - Remove the "Focus Stats" menu item.

- [ ] **Step 3: Self-check.**
  - **Point the existing code at the main window:** `isStatsVisible` becomes `isMainVisible`. The window lookup becomes title "FocusNow" with `mainState.page = .stats` first. Keep the external-relaunch wait.
  - **The relaunch must now land on Timer:** set `mainState.page = .stats` before writing `ready-for-reopen`, then note `page=` after.
  - **Add a `timer` phase.** It's on by default, after `settings`, and leaves the window open at 760×560. Each line below is noted, with `fields=` from `textFields(in:)`:
    1. `launch page=timer`.
    2. Capture `timer-idle` with `capture(contentView)`. Render a dark idle copy with `render(TimerPageView…frame(760,560), dark: true)`.
    3. Type "30" + Return into field 0, and note `focus field → settings=<focusMinutes> remaining=<engine.remainingSeconds>`. Set it back to 40.
    4. Type "6 sessions" + Return into field 3, and note `after field → <sessionsBeforeLongBreak>`. Set it back to 4.
    5. Call `engine.start()`, wait 0.6, capture `timer-running`, and note `running fields=`.
    6. `engine.pause()`, capture `timer-paused`.
    7. `engine.cancel()`, wait 0.6, capture `timer-after-cancel`, and note `after cancel fields=`.
    8. ⌘2 and ⌘1 through `NSApp.mainMenu?.performKeyEquivalent(with:)` with synthesized ⌘-key events. Note the page after each.
    9. Resize to 640×480 and capture `timer-idle-min`.
    10. Resize to 1400×900, start, and capture `timer-running-large`. Cancel, then resize back to 760×560.

- [ ] **Step 4: Run** `swift test 2>&1 | tail -3 && scripts/self-check.sh stats,settings,timer`. Expected:
  - The tests pass.
  - The log shows:
    - `launch page=timer` with fields=4;
    - `focus field → settings=30 remaining=1800`;
    - `after field → 6`;
    - `running fields=0`;
    - `after cancel fields=4`;
    - `⌘2 page=stats` then `⌘1 page=timer`;
    - after the external launch, `page=timer` with the main window visible;
    - popover Stats `page=stats`;
    - the stats and settings lines as before.
  - Read the captures:
    - idle: the timer side is wider than the configuration;
    - running: no configuration, the ring centred and larger;
    - min size: the configuration isn't clipped;
    - large: the ring scales up and the digits are whole;
    - stats: the toolbar switch is visible.

- [ ] **Step 5: Commit:** `git commit -m "feat: main window with Timer and Stats pages"`.

---

### Task 5: Typeable digits, then install

**Files:**
- Modify: `Sources/FocusNow/TimerParts.swift` (`TimerRing`), `Sources/FocusNow/PopoverView.swift`, `Sources/FocusNow/TimerPageView.swift`, `Sources/FocusNow/DebugSnapshots.swift`, `Sources/FocusNow/SelfCheck.swift`

**Interfaces:**
- Consumes: `TimerEngine.setNextFocus(minutes:)`, `TimerEngine.controls` (`.adjustLength` present ⇔ the length is adjustable), `LengthInput.minutes`.
- Produces:
  ```swift
  // TimerRing gains: init(engine: TimerEngine, diameter: CGFloat, editable: Bool = false, onBeginEditing: () -> Void = {})
  // DebugSnapshots:
  func press(accessibilityLabel: String, in window: NSWindow) async -> Bool
  ```

- [ ] **Step 1: Editable digits.**
  - While `editable && engine.controls.contains(.adjustLength)`, the digits are a plain `Button`:
    - accessibility label "Type the next session's length";
    - `.help("Click to type a length")`;
    - the I-beam cursor on hover, through `NSCursor`.
  - Clicking swaps in a centred `TextField`. It uses the same font, is prefilled with `"\(engine.plannedSecondsForNext / 60)"`, and is focused with all text selected. It calls `onBeginEditing()`.
  - Return or losing focus applies `LengthInput.minutes(_, in: TimerSettings.minuteRange)`:
    - a value goes to `engine.setNextFocus(minutes:)`;
    - nil reverts;
    - either way, editing ends.
  - Escape ends editing without applying.
  - If `.adjustLength` disappears mid-edit (a session started elsewhere), editing ends without applying.
  - On the Timer page, pass `editable: true`.
  - In the popover, pass `editable: true` and `onBeginEditing: { NSApp.activate() }` so keystrokes reach it.

- [ ] **Step 2: Self-check `digits` phase,** on by default after `timer`:
  - **`press`** finds the element by walking `accessibilityChildren()` from the window's content view and calls `accessibilityPerformPress()`. If that returns false, it clicks the centre of the element's `accessibilityFrame()` with synthesized mouse events. It returns whether the field appeared.
  - **Timer page:** note each of these:
    1. Press the digits, type "25" + Return → `digits 25 → remaining=1500`.
    2. Press, type "abc" + Return → `digits abc → 1500`.
    3. Press, type "50" + Escape → `digits escape → 1500`.
    4. Press, type "35", then `engine.start()` → `start mid-edit → planned=<active.plannedSeconds> fields=<count>`, then cancel.
    5. Press, type "180" + Return. Capture `timer-idle-180` and render `popover-180`.
    6. Reset with `setNextFocus(minutes: 40)`.
  - **Popover:** note each of these:
    1. `showPopover(fromClick: true)`, then press the digits in the popover's window.
    2. Note `popover editing active=\(NSApp.isActive)`.
    3. Type "35" + Return → `popover digits 35 → 2100`.
    4. Press again, type "20", then `closePopover()` → `popover closed mid-edit → <remaining>`.

- [ ] **Step 3: Run** `swift test 2>&1 | tail -3 && scripts/self-check.sh`. This is every phase.

  **Expected:**
  - The tests pass.
  - The digits lines:
    - remaining=1500, 1500, 1500;
    - `start mid-edit → planned=2400 fields=0`;
    - `popover editing active=true`;
    - `popover digits 35 → 2100`;
    - `popover closed mid-edit → 1200`.
  - The ring and popover captures at 180 show "3:00:00" whole.
  - Every earlier phase's lines are unchanged.

  If closing the popover mid-edit doesn't commit, make `TimerRing` commit when it disappears, and re-run.

- [ ] **Step 4: Commit:** `git commit -am "feat: type the next session's length into the digits"`.

- [ ] **Step 5: Install.** FocusNow is running from `/Applications`, and `scripts/build-app.sh --install` quits it, which logs a running session as ended early. **Ask the owner before running it.** Once they say yes, run it. Expected: `installed /Applications/FocusNow.app`.

- [ ] **Step 6: Hand-check list for the owner:**
  - real keystrokes into the popover digits while another app is frontmost;
  - the toolbar switch and ⌘1 and ⌘2;
  - the configuration hiding and returning;
  - typing a goal in Settings, if Task 3 ruled that synthesized typing couldn't reach it.
