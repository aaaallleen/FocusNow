# FocusNow v1 design

Date: 2026-11-19

Items marked **(call)** were decided by Claude, not by the owner. Everything else was decided by the owner in conversation.

## Intent

A personal, native macOS pomodoro timer to replace FocusPomo. FocusPomo has two problems for the owner: it has no menu bar presence, and its UI is an iPhone layout running on a Mac. FocusNow should feel like a Mac app, with the timer always visible in the menu bar.

The app is for one person on their own Mac. It is built and run locally, not distributed.

## Goals

- Run focus and break countdowns with configurable lengths.
- Show the live countdown in the menu bar, with controls one click away.
- Record every focus session and show accrued focus time by day, week, month, year and all time.
- Track progress against a daily focus goal.

## Non-goals for v1

These are planned as later, separately designed phases, in this order:

1. **Day schedule:** planning a day's focus cycles ahead of time.
2. **Calendar:** reading meetings through EventKit so the schedule works around them. Direct Google Calendar sign-in comes after EventKit.
3. **App usage monitoring.**

Not planned at all: task or project labels, app or website blocking, iCloud sync, an iPhone companion, Notification Center widgets, global hotkeys.

v1 must not block the later phases. The one concrete requirement is that a session record carries an origin field, so sessions started by a schedule can later be logged the same way as manual ones.

## Anti-goals

- A UI that looks like a phone app: oversized controls, full-screen single-column layouts, non-standard window behaviour.
- Focus totals that are wrong. Time must not be lost on sleep, quit or crash, and must not be inflated by paused or waiting time.
- Third-party dependencies.

## Constraints

- Swift and SwiftUI, with AppKit where SwiftUI falls short. Apple frameworks only.
- Minimum macOS 14 **(call)**. The development machine has Xcode 27.2, Swift 6.4 and macOS 27.2.
- The folder is not a git repository yet.
- The app icon source is `icon.png` in the project root: 1264×1264, no transparency, an hourglass on a cream rounded tile over a teal background with a long shadow.

## Approaches

1. **Swift/SwiftUI native (chosen).** No dependencies, a real menu bar item, and direct access to the APIs later phases need (EventKit, app activity). The owner chose this after seeing that the curated web library list (`pick-ui-library`) has a native equivalent for every task here.
2. **Electron or Tauri with a TypeScript frontend.** Would let the curated React libraries apply directly. Rejected because a web view in a tray popover is the non-native feel the owner is leaving, the bundle is far larger, and the calendar and app-monitoring phases would need native bridges.

Native equivalents used in place of the curated web libraries:

| Task | Native choice |
| --- | --- |
| Popover and controls | SwiftUI controls in a popover |
| Animation | SwiftUI springs and transitions |
| Charts | Swift Charts |
| App state | `@Observable` model |
| End-of-session alert | `UserNotifications` |
| Storage | SwiftData **(call)** |

## The app's surfaces

### Menu bar item

Always present while the app runs. It shows a glyph plus the remaining time in monospaced digits.

| State | Appearance |
| --- | --- |
| Idle | Glyph only |
| Focusing | Glyph and `18:42` |
| Paused | Pause glyph and the frozen time, dimmed |
| Break | Break glyph and time, tinted differently from focus |
| Finished, waiting | Flashes until the owner clicks it |

- The glyph is an hourglass template image, to match the app icon **(call)**.
- The flash is an opacity pulse, not movement.

Because the popover must open by itself and the item must flash, build the item with `NSStatusItem` and `NSPopover` hosting SwiftUI, not SwiftUI's `MenuBarExtra` **(call)**.

### Popover (layout A, "Ring")

Opens on clicking the menu bar item. About 230pt wide. Top to bottom:

1. Phase label and cycle position, e.g. `FOCUS · 2 of 4`.
2. A progress ring with the remaining time in its centre.
3. Controls for the current state (see below).
4. Today's focus total, the daily goal, and a bar showing progress toward it.
5. A footer with **Stats**, **Settings** and **Quit**. Quit fully exits the app. The footer layout is a **(call)**; the Quit button is required.

Controls by state:

| State | Controls |
| --- | --- |
| Idle | Adjust this session's length, **Start** |
| Focusing | **Pause**, **End early**, **Cancel** |
| Paused | **Resume**, **End early**, **Cancel** |
| Break running | **Pause**, **Skip** |
| Focus finished, waiting | **Start break**, **Skip break** |
| Break finished, waiting | **Start focus** |

- **End early** finishes the session and logs the time actually focused.
- **Cancel** discards the session; nothing is logged **(call)**.
- Adjusting the length while idle changes only the next session, not the default in Settings **(call)**.

### Stats window

A standard resizable Mac window, as mocked up in `.superpowers/brainstorm/69458-1795079963/content/stats-window.html`.

- **Five tiles across the top:** Today, This week, This month, This year, All time. Each shows the focus total and a secondary line (goal for Today, session count for the others). Clicking a tile selects that range.
- **A bar chart** for the selected range, with arrows to page to earlier periods and a summary line (daily average, days the goal was met).
- **A session list** under the chart, marking sessions that ended early. Clicking a bar selects it, and the list shows the sessions in that bar's period (an hour, a day, a month or a year). With no bar selected it shows today's sessions, or the most recent day with sessions when paging through earlier periods **(call)**.

Chart granularity **(call)**:

| Range | Bars |
| --- | --- |
| Today | Per hour |
| Week | Per day, with the goal as a dashed line |
| Month | Per day, with the goal line |
| Year | Per month |
| All time | Per month, switching to per year past two years of data |

### Settings window

A standard Settings window (⌘,) **(call)** with:

- Focus length, short break length, long break length.
- Number of focus sessions before a long break.
- Daily focus goal.
- Sound on or off.
- Launch at login.

Defaults: 40 min focus, 5 min short break, 15 min long break (owner's decision). Long break after every 4th focus session, 4 h daily goal, sound on, launch at login off **(call)**.

### Dock icon

- The Dock icon is hidden while the app is only in the menu bar.
- Launching the app from Spotlight, Launchpad or Finder shows the Dock icon and opens the stats window. This also applies when the app is already running.
- Closing the last window hides the Dock icon. The app keeps running in the menu bar.
- Opening Stats or Settings from the popover also shows the Dock icon while that window is open **(call)**.
- Launching at login starts in the menu bar only, with no window **(call)**.
- The app exits only through Quit (popover button or ⌘Q).

App icon: crop `icon.png` to the cream tile so the tile is the icon, instead of using the full image with the teal background around a small tile. The crop is about 720px, so the largest icon size is slightly upscaled. The owner may replace the icon later, so keep it a single swappable asset.

## Timer behaviour

### Cycle

Focus → short break → focus → … with a long break after every Nth focus session (N from Settings).

- Nothing auto-advances. When a countdown reaches zero the app waits for the owner.
- Time spent waiting is not counted as anything.
- A session that ended early counts toward the cycle; a cancelled one does not **(call)**.
- The cycle position resets after a long break and at the start of a new day **(call)**.
- Skipping a break moves straight to the next focus session, ready to start.

### When a countdown reaches zero

All of these happen together:

1. The menu bar item starts flashing.
2. The popover opens by itself, showing the next action (**Start break** or **Start focus**). It should not steal keyboard focus from the app the owner is typing in **(call)**.
3. A system notification is posted.
4. If sound is on in Settings, the app plays its own end-of-session sound. It plays even when Do Not Disturb or a Focus mode is silencing notifications, and even if notification permission was denied, so it must not rely on the notification's sound.

The flashing stops when the owner clicks the menu bar item or starts the next phase.

### Accuracy

- The countdown is computed from wall-clock timestamps, not from counting ticks, so sleep and timer drift cannot distort it.
- Paused time is excluded from a session's focused time.
- Time has three kinds: **focus**, **rest** (breaks) and **blank**. Blank is everything else: the Mac asleep, a paused session, and waiting for the owner to start the next phase. Blank time never counts toward focus or rest.
- When the Mac sleeps during a focus session or a break, the session pauses at the moment of sleep. On wake it is still paused with its remaining time intact, and the owner resumes, ends early or cancels. The pause-on-sleep mechanism is a **(call)**; that sleep is blank time is the owner's decision.
- Blank time is not stored as its own record **(call)**. It is the gap between a session's wall-clock span and its `activeSeconds`, and the gaps between sessions. v1 does not display blank time.
- Quitting during a focus session logs it as ended early with the time focused so far **(call)**.
- The running session is checkpointed to disk about every 15 seconds. After a crash or forced shutdown, the next launch logs the session as ended early at the last checkpoint **(call)**.

## Data

One record per finished session:

| Field | Meaning |
| --- | --- |
| id | Unique identifier |
| kind | focus, short break or long break |
| startedAt | When it started |
| endedAt | When it finished |
| plannedSeconds | The length it was set to |
| activeSeconds | Time actually spent, excluding pauses |
| outcome | completed or ended early |
| origin | manual (later: schedule) |

Rules:

- Stats use `activeSeconds` of focus sessions only. Breaks are stored but never shown in totals.
- Cancelled sessions are not stored.
- A focus session ended early with under 60 seconds of active time is discarded **(call)**.
- A session belongs to the local calendar day it started on, even if it crosses midnight **(call)**.
- The week's first day follows the system setting.
- Each change to the daily goal is recorded with its date. A past day is judged against the goal in force on that day, so changing the goal never rewrites history **(call)**.
- Data is stored locally in the app's Application Support folder.

## Look and motion

- **Colour:** take the accent from the app icon. Teal for focus and a warm cream-amber for breaks, replacing the red in the mockups. Follow the system light and dark appearance. The owner may change the palette later, so define the colours in one place.
- **Type:** system font, with tabular digits for every time value so widths do not jitter.

Motion rules, from the `emil-design-eng` skill translated to SwiftUI:

- The countdown digits change instantly, with no per-second animation.
- The ring sweeps continuously and linearly.
- Buttons scale to 0.97 on press over about 150ms, ease-out.
- The popover uses the system's open behaviour, with no custom entrance.
- The finish moment may have a subtle spring as the ring completes and the controls crossfade to the next action.
- Phase changes crossfade colour and label over about 200ms.
- With Reduce Motion on, the pulse and spring become plain fades.

## Testing

- The timer and cycle logic lives apart from the UI and takes an injectable clock, so pause, end early, cancel, pause-on-sleep, midnight and crash-recovery cases are covered by unit tests without waiting in real time.
- The stats aggregation (totals per range, chart buckets, goal-met days) is unit tested against fixed session data.
- The UI is checked by running the app.

## Left to the builder

- Project layout and whether the build uses an Xcode project or a Swift package.
- App name spelling in the UI ("FocusNow" unless the owner says otherwise) and the bundle identifier.
- The exact glyphs, spacing, colours within the palette above, and notification wording.
- How the Dock icon is shown and hidden (activation policy switching is the expected route).
- Signing for local use, including whatever notifications and launch at login need.
