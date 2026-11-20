# FocusNow Settings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings becomes the main window's third tab, with a sidebar for Cycle, Goal and General. The cycle lengths move there from the Timer page, which keeps one full-page layout.

**Architecture:** This change is app-target only; no `FocusNowCore` logic changes.
- `MainPage` gains `.settings`, and `MainWindowState` gains the selected `SettingsSection`.
- `SettingsView` becomes a sidebar plus a grouped-form pane.
- `WindowCoordinator` loses the separate settings window.
- `TimerPageView` loses its configuration column.

The in-process self-check is the test for each task. Each task first updates the self-check to expect the new behaviour and runs it red, then implements, then runs it green.

**Tech Stack:** Swift 6, SwiftUI hosted in AppKit, Swift Testing. Apple frameworks only.

**Spec:** `docs/superpowers/specs/2026-11-19-focusnow-settings-tab-design.md`. It builds on the timer-page and v1 specs.

## Global Constraints

- **Platform:** Apple frameworks only. Minimum macOS 14, so no macOS 15-only API.
- **Colours:** live only in `Theme.swift`.
- **Digits:** never animate.
- **Typed values:**
  - Lengths are 1–180 min and Long break after is 1–12 sessions. The goal is `TimerSettings.goalRange`.
  - Return or leaving a field commits; Escape reverts. Out-of-range values clamp. Unparseable text beeps and reverts; cleared text reverts quietly.
- **Switching:** switching tabs or sections is not animated.
- **Testing:** test each step before the next. Every task ends with `swift test` and a self-check run whose log you read. The self-check only runs against `FOCUSNOW_DATA_DIR`.
- **Your running copy:** never quit or replace the owner's running `/Applications/FocusNow.app` without asking. Never activate other apps on the owner's machine.
- **Commits:** end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Typed text that hasn't been committed** survives each of these:
   - switching section;
   - switching tab (⌘1);
   - closing the window.

   It's checked in Task 1.
2. **Cycle edited during a running session:**
   - the running session's planned length is unchanged;
   - the next idle timer shows the new Focus.

   It's checked in Task 1.
3. **Every way into Settings** lands on the Settings tab with the Dock icon showing: ⌘,, ⌘3, the popover's Settings button, and the toolbar. It's checked in Task 1.
4. **The minimum window size (640×480)** doesn't clip the Cycle pane: its four rows, units and steppers are all visible. It's checked by a screenshot in Task 1.
5. **Timer page:**
   - no fields;
   - the same ring size idle and running;
   - the digits, −/+ and Start still commit typed digits.

   It's checked in Task 2.

---

## File Structure

```
Sources/FocusNow/
  MainWindowView.swift     MainPage.settings, MainWindowState.settingsSection, third segment
  SettingsView.swift       SettingsSection; sidebar + Cycle / Goal / General panes
  WindowCoordinator.swift  settings window removed
  AppDelegate.swift        showSettings() → main window on Settings; ⌘3 in Window menu
  TimerPageView.swift      one layout, configuration removed (Task 2)
  Theme.swift              layoutShift removed (Task 2)
  SelfCheck.swift          settings phase drives the tab; timer/commits phases updated
```

---

### Task 1: Settings tab with a sidebar

**Files:**
- Modify: `Sources/FocusNow/MainWindowView.swift`, `SettingsView.swift`, `WindowCoordinator.swift`, `AppDelegate.swift`, `SelfCheck.swift`.

**Interfaces:**
- Produces:
  - `enum MainPage { case timer, stats, settings }`.
  - `enum SettingsSection: String, CaseIterable, Identifiable { case cycle, goal, general }`, with:
    - `title: String` ("Cycle", "Goal", "General");
    - `symbol: String`;
    - `identifier: String` ("settings-section-cycle", …).
  - `MainWindowState.settingsSection: SettingsSection = .cycle`.
  - `SettingsView(settings:state:)`.
  - `AppDelegate.showSettings()` sets `mainState.page = .settings` and calls `windows.showMain()`.
- Removed:
  - `WindowCoordinator.showSettings`, `isSettingsVisible`, `settingsContentView`;
  - the `makeSettings:` init parameter.

- [ ] **Step 1: Write the failing self-check.** Rewrite `checkSettings` in `SelfCheck.swift` to drive the tab. Log these lines:
  - **Menus:** `menu: Settings… key="," … Window menu=[…]`. Window menu wants `Timer`, `Stats`, `Settings`.
  - **⌘, through the real menu item:** `after ⌘,: mainVisible=true page=settings section=cycle policy=regular (Dock icon)`. Capture `settings-cycle`, light and dark.
  - **Cycle fields** (moved from `checkTimer`, same lines and wants), plus VoiceOver for AXTextField and AXIncrementor:
    - `focus field → settings=30 remaining=1800`;
    - `after field → 6`;
    - `defaults kept after blur`;
    - the one-off line.
  - **During a session:** type 35 into Focus, commit, then check `running: planned=2400 focus=35`. Cancel, then check `idle after: remaining=2100`. Reset Focus to 40.
  - **Sidebar:** press identifier `settings-section-goal` and log `section=goal fields=1`. Capture `settings-goal`. Run the existing goal-typing lines unchanged.
  - **General:** press `settings-section-general` and log `section=general toggles=2`, counting `NSButton`s with switch/checkbox type, or AX role `AXCheckBox`. Capture `settings-general`.
  - **Typed text that hasn't been committed:**
    - Go back to Cycle, type "33" into Focus, press General, and log `focus 33 then General → 33`.
    - Type "34" into Focus, then ⌘1, and log `focus 34 then ⌘1 → 34 page=timer`.
    - Open Settings, type "36" into Focus, close the window, and log `focus 36 then close → 36`.
    - Reset Focus to 40.
  - **Other ways in:**
    - ⌘3 through `performKeyEquivalent`: `⌘3 handled=true page=settings`.
    - The popover's Settings path (`showSettings()` after `statusItem.showPopover(fromClick: true)`): `popover Settings: popoverVisible=false page=settings`.
  - **Minimum size:** capture `settings-cycle-min` at 640×480.
  - **Unchanged:** the goal → 3h and sound-off lines, then `after closing Settings: policy=accessory (no Dock icon)`.

- [ ] **Step 2: Run red.** Run `swift build 2>&1 | tail -3`. Expected: it fails, because `MainPage.settings` and `SettingsSection` don't exist yet. That is the red for this task. The app can't express the new behaviour until those types exist.

- [ ] **Step 3: Implement.**
  - **`MainWindowView`:**
    - adds the `Settings` segment;
    - `.settings` shows `SettingsView(settings:state:)`.
  - **`SettingsView`:**
    - Layout: an `HStack(spacing: 0)` holding a `List(selection: $state.settingsSection)` with `.listStyle(.sidebar)`, width 180; then a `Divider`; then the selected pane.
    - Each list row is `Label(title, systemImage: symbol)` with `.tag(section)` and `.accessibilityIdentifier(identifier)`.
    - The pane is a `Form { … }.formStyle(.grouped)`.
    - **Cycle** shows the four `LengthField`s from `TimerPageView.rows` in `LabeledContent` rows, with the same labels, ranges, VoiceOver labels and unit width.
    - **Goal** and **General** keep their current contents.
    - The list must not deselect to nil. Use a binding that ignores nil.
  - **`WindowCoordinator`:**
    - Remove the settings window and its accessors.
    - `windowWillClose` drops the activation policy to accessory when the main window closes.
  - **`AppDelegate`:**
    - `showSettings()` closes the popover, sets the page to `.settings`, and shows main.
    - Add a Window menu item "Settings" with ⌘3, targeting `openSettings`.
    - `makeSettings` goes away.
  - **Timer page:** leave `TimerPageView` alone in this task. The cycle fields show on both pages until Task 2.

- [ ] **Step 4: Run green.** Run `swift test 2>&1 | tail -3 && scripts/self-check.sh stats,settings,timer`. Expected:
  - all 146 tests pass;
  - every settings line above shows its want;
  - the timer phase is unchanged from the last run;
  - the screenshots show the sidebar with the selection highlighted, and no clipping at 640×480 in light or dark.

  Look at the PNGs.

- [ ] **Step 5: Commit.** Run `git commit -am "feat: Settings tab with Cycle, Goal and General"`.

### Task 2: Timer page is only the timer

**Files:**
- Modify: `Sources/FocusNow/TimerPageView.swift`, `TimerParts.swift` (ring identifier), `Theme.swift`, `SelfCheck.swift`, and the timer-page spec (one superseded note).

**Interfaces:**
- Consumes: Task 1's Cycle pane (now the only place the cycle lengths are edited).
- Removed: `TimerPageView.timerShare`, `configuration`, `rows`, `ConfigRow`; `Theme.layoutShift`.

- [ ] **Step 1: Write the failing self-check.** Update `checkTimer`:
  - **Remove** the field-typing block, which moved to settings in Task 1.
  - **Log these lines:**
    - `launch page=timer … fields=0`;
    - `running fields=0`;
    - `ring idle=<diameter> running=<diameter> (want equal)`.
  - **Ring diameter:** add `static let ringIdentifier = "timer-ring"` to `TimerRing`, put `.accessibilityIdentifier` on its ZStack, and read that element's AX frame width.
  - **VoiceOver:** wants only `AXButton` lines:
    - "40:00" with its hint;
    - "Five minutes shorter";
    - "Five minutes longer";
    - "Start focus".

  Update `checkCommits`:
  - Remove `focus field 25 then Start`, `focus field 30 then popover Start`, `focus field 25 then stepper up` and `focus field 35 then ⌘2`. Task 1 covers the field cases now.
  - Keep `digits 25 then Start → planned=1500`, `digits 25 then + → remaining=1800`, and the finish lines.

  Run `scripts/self-check.sh timer`. Expected: red. `fields=4` is still logged, and the ring diameters differ.

- [ ] **Step 2: Implement.**
  - **`TimerPageView`:**
    - The body is the timer column at full size, with `diameter = max(min(min(w, h) * 0.7, h - 170), 120)` and `inSession` spacing always.
    - Keep the `PendingEdits` environment, since the digits use it.
  - **Remove:**
    - the column, configuration and rows;
    - the layout animation and its Reduce Motion `.id`.
  - **Clean up:**
    - Remove `Theme.layoutShift` if nothing else uses it.
    - Update the doc comment.
  - **Timer-page spec:** add one line under "Timer page, no session running": "Superseded by the settings-tab spec: the configuration moved to Settings → Cycle."

- [ ] **Step 3: Run green.** Run `swift test 2>&1 | tail -3 && scripts/self-check.sh`. That's every phase. Expected:
  - all tests pass;
  - `fields=0` everywhere on the timer page;
  - the ring is equal idle and running;
  - the digits, commits, outside and popover phases match their previous wants;
  - the log ends with "quitting with a running session".

  Look at `timer-idle`, `timer-idle-min`, `timer-running` and `timer-running-large`.

- [ ] **Step 4: Commit.** Run `git commit -am "feat: Timer page is only the timer; cycle lives in Settings"`.

### Task 3: Review and hand over

- [ ] **Step 1: Review.** Dispatch a fresh reviewer on the most capable model for `git diff 93ed481..HEAD`, with this spec and the Review Focus above. Fix Critical and Important findings test-first: add a self-check line, see it red, then green. List any minors.
- [ ] **Step 2: Install.** Ask the owner to run `! scripts/build-app.sh --install`. It quits the running `/Applications` copy. Don't run it for them.
