# FocusNow: Settings as a third tab

A small change on top of the Timer page (`docs/superpowers/specs/2026-11-19-focusnow-timer-page-design.md`). That doc and v1's still bind where this one is silent; this one replaces their "Settings window" and "Timer page, no session running" sections.

## Why

All configuration should live in one place, with room to grow. A calendar section comes next. The Timer page becomes just the timer.

## Goals

- The main window has three tabs: **Timer | Stats | Settings**.
- Settings has a sidebar on the left that picks a section. The sections are **Cycle**, **Goal** and **General**.
- The cycle's lengths move from the Timer page to Settings → Cycle.
- Adding Calendar later means adding one more sidebar item.

## Non-goals

- No change to the engine, the stats, or the popover's layout.
- No calendar yet.

## Approaches

- **A plain fixed sidebar list beside a content pane, inside the Settings tab.** *Picked:* it's the one sensible way.
- **macOS's split view (`NavigationSplitView`).** It would put a sidebar toggle in the window's shared toolbar. That toggle would have to come and go as tabs switch, which isn't worth it for 3–4 items.

## Design

### Window and shortcuts

- The toolbar switch reads **Timer | Stats | Settings**. ⌘1, ⌘2 and ⌘3 switch tabs, and the Window menu lists all three.
- ⌘, (FocusNow → Settings…) opens the main window on the Settings tab. So does the popover's Settings button.
- The separate Settings window goes away. The Dock icon shows while the main window is open, as before.
- Switching tabs isn't animated, as before.

### Settings tab

```
              [ Timer | Stats | Settings ]
┌─────────────┬──────────────────────────────────────┐
│ ⟳ Cycle     │  Focus             [ 40 ] min      ⌃⌄ │
│ ◎ Goal      │  Short break       [  5 ] min      ⌃⌄ │
│ ⚙ General   │  Long break        [ 15 ] min      ⌃⌄ │
│             │  Long break after  [  4 ] sessions ⌃⌄ │
└─────────────┴──────────────────────────────────────┘
```

- **Sidebar:**
  - It's a fixed column with one item per section. Each item has an icon and a title-case name (macOS convention).
  - It opens on Cycle and remembers the last section while the app runs.
- **Panes:** each section's pane uses the grouped form look of System Settings.
  - **Cycle:**
    - Focus, Short break and Long break: 1–180 min each.
    - Long break after: 1–12 sessions.
    - Each has a text field and a stepper, with the same typing rules as before.
  - **Goal:** the daily focus goal, with the same typing rules as before.
  - **General:**
    - Play sound when a session ends.
    - Launch at login.
- **During a session:** the cycle lengths stay editable while a session runs or is paused. Changes apply from the next session. This matches how the old Settings window behaved.
- **Unfinished edits:** typed text that hasn't been committed still applies in these cases:
  - you switch tabs or sections;
  - you close the window.

### Timer page

- It has one layout: the timer fills the page whether or not a session is running. It's the old "session running" layout.
- The 0.3 s widen and shrink when a session starts or ends goes away.
- The digits and −/+ still set the next session's length.

## Testing

The app self-check runs against the scratch data dir. It checks these things:

- **Getting to Settings:** ⌘, and the popover's Settings button land on Settings, and ⌘3 switches to it.
- **Sidebar:** the sidebar switches panes.
- **Typed values reach the right place:**
  - typed cycle values reach the settings and the idle timer;
  - a typed goal follows the existing rules.
- **Unfinished edits:** a value typed and not yet committed survives each of these:
  - switching tabs;
  - switching sections;
  - closing the window.
- **During a session:** editing a cycle length while a session runs leaves the running session alone.
- **Timer page:**
  - it has no fields;
  - its layout is the same idle and running;
  - it works at the minimum and large window sizes.
- **VoiceOver:** it reads each field's name.

Each step is tested before the next starts.

## Left to the builder

- Sidebar width, icons, spacing.
- Whether the section name also heads the pane.
