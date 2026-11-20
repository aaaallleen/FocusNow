# FocusNow: Timer page and typed lengths

A small change on top of v1 (`docs/superpowers/specs/2026-11-19-focusnow-v1-design.md`, still binding where this doc is silent).

## Why

Opening FocusNow from Spotlight or the Dock only shows stats today; the timer lives only in the menu bar popover. The owner wants the app window to be a proper pomodoro timer they can configure and start, with stats one click away. They also want to type a length directly instead of only clicking −/+ or the steppers.

## Goals

- The app window has two pages: **Timer** (first) and **Stats** (second).
- The Timer page shows the timer and the cycle's configuration, and starts a focus.
- Once a session starts, the configuration hides and the timer fills the window.
- Every length can be typed: the Timer page, the popover, and Settings.

## Non-goals

- No change to the engine's rules (cycle, blank time, sleep, logging) or to the stats themselves.
- No keyboard shortcut to start or pause.
- The window never enters macOS full screen on its own; "fills the window" means the window. The green button still gives real full screen.

## Approaches

- **A. A bigger popover.** Ring and controls; type the next session's length into the digits; cycle lengths stay in Settings. Smallest change, but the configuration stays two clicks away.
- **B. Ring with the cycle configuration beside it.** *Picked*, with the owner's changes: the timer side is the larger one, the configuration hides once a session starts, and the timer then fills the window.

## Design

### Window

- One main window titled "FocusNow" replaces "Focus Stats": default 760×560, minimum 640×480, frame remembered.
- A segmented **Timer | Stats** switch sits in the toolbar. ⌘1 and ⌘2 switch pages; the Window menu lists both.
- Spotlight, the Dock, and the Window menu's Timer item open the Timer page. The popover's Stats button opens the Stats page.
- Dock icon behaviour is unchanged: it shows while the window is open and hides when it closes.

### Timer page, no session running

> Superseded by `2026-11-19-focusnow-settings-tab-design.md`: the configuration moved to Settings → Cycle, and the Timer page keeps the session layout at all times.

```
                    [ Timer | Stats ]
  ┌───────────────────────────────┬────────────────────────┐
  │         FOCUS · 1 of 4        │ Focus       [ 40 ] min ⌃⌄│
  │          ╭────────╮           │ Short break [  5 ] min ⌃⌄│
  │          │ 40:00  │           │ Long break  [ 15 ] min ⌃⌄│
  │          ╰────────╯           │ Long break after         │
  │    [ − ][ + ][ Start focus ]  │             [  4 ] sessions ⌃⌄│
  │   Today 1h 20m ▬▬▬░░░ Goal 4h │                        │
  └───────────────────────────────┴────────────────────────┘
          timer ≈ 62%                 configuration ≈ 38%
```

- The left side is the popover's layout at a larger size: phase label, ring with digits, the same controls as the popover, and Today/Goal.
- The right side edits the defaults for every session: Focus, Short break and Long break (1–180 min), and Long break after (1–12 sessions). Each has a text field and a stepper. These are the same values Settings held.
- Clicking the digits (only before a focus starts) lets you type the **next session's** length, the same as the popover's −/+.
- The configuration shows whenever no session is running or paused. That includes a pending break.

### Timer page, session running or paused

```
                    [ Timer | Stats ]
  ┌────────────────────────────────────────────────────────┐
  │                     FOCUS · 1 of 4                     │
  │                      ╭──────────╮                      │
  │                      │  38:12   │                      │
  │                      ╰──────────╯                      │
  │                [ Pause ][ End early ][ Cancel ]        │
  │               Today 1h 20m ▬▬▬░░░ Goal 4h              │
  └────────────────────────────────────────────────────────┘
```

- The configuration hides. The ring grows to about 70% of the window's shorter side, and the digits scale with it.
- This applies to focus and to breaks. The configuration returns when the session finishes, ends early, is skipped or is cancelled.

### Motion

- Hiding or showing the configuration takes 0.3 s with a strong ease-in-out (it's on-screen movement). The configuration fades out and shifts 12 pt right while the timer column widens and the ring grows.
- With Reduce Motion, this becomes a crossfade with no growth.
- Digits never animate, as in v1.

### Typed lengths

- **Lengths are whole minutes.** "25", "25m" and "25 min" all mean 25 minutes. A value commits on Return or when you leave the field; Escape reverts.
- Out-of-range values clamp to the field's range. Anything unparseable reverts to the previous value.
- **Daily goal (Settings)** accepts "4h", "3h 30m", "3:30", "4" (hours) or "90m", and clamps to 15 min–16 h.
- **Popover:** clicking the digits before a focus starts lets you type the next session's length.
- The −/+ buttons keep their 5-minute steps, but their range becomes 1–180 to match typing. This fixes v1 deferred minor 2: − no longer raises a 3-minute session to 5.
- Changing the default Focus length drops any one-off length, so the digits always show what you just set. This fixes v1 deferred minor 3.

### Settings window

- Settings keeps Goal (now typeable) and General.
- Its Timer section moves to the Timer page.

## Testing

- **Core unit tests (Swift Testing):**
  - parsing typed minutes and goals;
  - typing the one-off length (clamping; only before a focus);
  - the −/+ range;
  - the one-off dropping when the Focus default changes;
  - the page's "show configuration" rule.
- **App self-check, against the scratch data dir:**
  - the window opens on Timer with the configuration shown;
  - Start hides the configuration and grows the ring;
  - Cancel brings the configuration back;
  - typed values reach the settings and the engine;
  - ⌘1 and ⌘2 switch pages;
  - an external relaunch lands on Timer;
  - the popover's Stats button lands on Stats.
- Each step is tested before the next starts, as in v1.

## Left to the builder

Exact spacing, font sizes, and the field widths.
