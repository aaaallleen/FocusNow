# FocusNow: Appearance and polish

Builds on v1, the Timer page, the Settings tab and the Calendar designs (all `2026-11-19-focusnow-*-design.md`). Those still bind where this one is silent.

Items marked **(call)** were decided by Claude, not by the owner. Everything else was decided by the owner in conversation, mostly by approving proposals and two browser mockups (`.superpowers/brainstorm/*/content/colorways.html`, `appearance-settings.html`).

## Why

The owner keeps a local list of improvements after using the app day to day. This design covers all seven items on it, plus a new app icon:

1. Start focus fills its own row; − and + move to the row below and share it.
2. In Settings → Cycle, the units ("min", "sessions") sit right, against the steppers.
3. A Light / Dark switch in Settings.
4. Colourways: "sets of predefined colorways, these colorways change the color of buttons, countdown circle, stats, and icon color. It doesn't impact the overall theme." Then: 8 presets, plus a custom colourway of 4 colours, with "where each color goes" written next to each colour.
5. A focus length set on the Timer page should stay: cancelling or finishing must not put the default back.
6. "The gap between the countdown circle and the buttons don't scale when height grows … on a full height, the circle and the buttons collide."
7. Calendar events under the timer show their start and end time.
8. The owner redrew the logo as `icon.svg`; the app icon is built from it, from a copy kept in its own folder.

## Goals

- Every item above works in the main window and, where it applies, in the menu bar popover.
- Choosing a colourway or the light/dark mode applies straight away, everywhere, without losing anything on screen.
- Nothing overlaps at any window size, from the 640 × 480 minimum to full screen.

## Non-goals

- Recolouring the app icon or the menu bar icon. The owner: "icon color" means "the icons for settings, calendar etc", which are the Settings sidebar icons.
- Changing how macOS draws the rest of the app: window backgrounds, text, sidebar selection, checkboxes, switches, segmented controls, and the calendar dots (which keep each calendar's own colour).
- More than one custom colourway, naming it, or sharing colourways **(call)**.
- Transparency in custom colours **(call)**.
- Tinting the popover footer's Stats / Settings / Quit icons **(call)**: they stay grey like the text beside them.

## Anti-goals

- The "overall theme" changing with the colourway.
- Text that can't be read on a colour the owner picks.
- Existing settings, history or the running session lost or reset by any of this.
- The Timer page jumping when a session starts or ends.
- The ring and the buttons touching, at any size.
- The self-check changing the owner's real preferences or touching the installed app (standing rule: it runs only against `FOCUSNOW_DATA_DIR`, takes no intrusive actions, never replaces `/Applications/FocusNow.app`).
- Committing the icon files: they stay local, like `icon.png` today.

## Constraints

- Swift 6, SwiftPM, AppKit + SwiftUI, macOS 14+. Apple frameworks only.
- Logic that can be tested lives in `FocusNowCore` with unit tests; views live in the app target and are checked by the self-check.
- New preferences are stored under their own `UserDefaults` keys, as `CalendarPreferences` does, so the existing `TimerSettings` keeps decoding. Unknown or damaged values fall back to the defaults.

## Approaches

| Question | Options | Picked |
| --- | --- | --- |
| How the colourway reaches every screen | **One Appearance store every screen watches**: a change repaints straight away and keeps what's on screen. **Global colours, rebuild the window on change**: less code, but loses a half-typed length, the Stats period, the Settings section. **macOS accent colour**: one colour only (no break colour) and recolours checkboxes and switches. | The store (owner) |
| What the 4 custom colours are | **Focus and break, each in light and dark**, as the four dots under each preset. **One colour each for buttons, ring, Stats and icons.** | Focus/break × light/dark (proposed, owner approved the mock) |
| Keeping a set focus length | **It stays until changed again, separate from the Settings default; changing Focus in Settings replaces it.** **The Timer page writes the Settings default.** | Stays until changed (proposed; owner didn't object) |
| Building the app icon | **AppKit draws the SVG directly** (checked: it renders faithfully). **Export a PNG and crop it**, as today. | Draw the SVG **(call)** |

## Design

### 1. Timer buttons in two rows

Every state shows two rows, so the column's height never changes:

| State | Top row (full width) | Second row (shares the width equally) |
| --- | --- | --- |
| Idle, focus next | Start focus | − · + |
| Idle, break next | Start break | Skip break |
| Focus running | Pause | End early · Cancel |
| Focus paused | Resume | End early · Cancel |
| Break running | Pause | Skip |
| Break paused | Resume | Skip |

- The top row is the main action, in the phase colour. The second row's buttons are the plain style.
- − and + keep their accessibility labels ("Five minutes shorter", "Five minutes longer").
- Same layout in the popover (230 pt wide) and on the Timer page (up to 320 pt wide).
- Which control goes in which row is decided in the core library, next to the existing `controls`, and unit-tested **(call)**.

### 2. Cycle units against the steppers

In Settings → Cycle the unit column keeps its fixed width, but "min" and "sessions" are right-aligned in it, so each sits next to its stepper. The number fields stay right-aligned and lined up as today.

```
Focus               [ 40 ]      min ⇕
Short break         [  5 ]      min ⇕
Long break after    [  4 ] sessions ⇕
```

### 3. Settings → Appearance

A new section, last in the sidebar: **Cycle, Goal, General, Calendar, Appearance**, with the `paintpalette` symbol **(call)**.

```
┌─────────────┬────────────────────────────────────────────────┐
│ ⟳ Cycle     │  Appearance          [ System | Light | Dark ] │
│ ◎ Goal      │                                                │
│ ⚙ General   │  COLORWAY                                      │
│ ▦ Calendar  │  ◐ Teal & Amber   ◐ Sage & Clay   ◐ Indigo & … │
│ ◑ Appearance│  ◐ Plum & Gold    ◐ Ocean & Coral ◐ Forest & … │
│             │  ◐ Rose & Mint    ◐ Graphite & …  ◍ Custom     │
│             │                                                │
│             │  YOUR COLORS            (only when Custom)     │
│             │  [■] ① Focus, light mode                        │
│             │       The ring and the main button during …     │
│             │  [■] ② Focus, dark mode   …                     │
│             │  [■] ③ Break, light mode  …                     │
│             │  [■] ④ Break, dark mode   …                     │
│             │                                                │
│             │  PREVIEW                                       │
│             │  ┌ Light ─────────────┐┌ Dark ──────────────┐  │
│             │  └────────────────────┘└────────────────────┘  │
└─────────────┴────────────────────────────────────────────────┘
```

**Appearance** — System (default), Light or Dark. Light and Dark force the main window and the popover into that mode; System follows the Mac. The menu bar item always follows the menu bar. Applies immediately.

**Colorway** — nine tiles in a 3 × 3 grid: the eight presets, then Custom. Each preset tile shows a circle split between its focus and break colours (light-mode shades) and its name; Custom shows a multicolour circle. The chosen tile is outlined in the system selection colour. Default: Teal & Amber.

| ID | Name | Focus, light | Focus, dark | Break, light | Break, dark |
| --- | --- | --- | --- | --- | --- |
| teal | Teal & Amber | #336B82 | #6BB0C9 | #CC9433 | #E9BA66 |
| sage | Sage & Clay | #4E7A5B | #8FBF9B | #C0704A | #E59B79 |
| indigo | Indigo & Peach | #4A54A6 | #939BEB | #D27F57 | #F2AB88 |
| plum | Plum & Gold | #7B4B87 | #C696D2 | #B38A2A | #E3C264 |
| ocean | Ocean & Coral | #1F6DAE | #6DAFE9 | #D85F57 | #F29C94 |
| forest | Forest & Rust | #2E6A4E | #76B996 | #B0532C | #E38C66 |
| rose | Rose & Mint | #A8476A | #E58DAA | #3A9580 | #7ACFB9 |
| graphite | Graphite & Citron | #474D56 | #BAC1CB | #8E9C2E | #C9D86B |

Teal & Amber is exactly today's colours, so nothing changes for the owner until they pick another.

**Your colors** — shown only while Custom is chosen. Four rows, each a colour well (the macOS colour panel, no opacity), a number, a title and where the colour goes:

1. **Focus, light mode** — "The ring and the main button during focus, the goal bar, the Stats charts and calendar blocks, and the Settings sidebar icons, in light mode."
2. **Focus, dark mode** — "The same places as color 1, in dark mode."
3. **Break, light mode** — "The ring and the main button during a short or long break, and the menu bar timer during a break, in light mode."
4. **Break, dark mode** — "The same places as color 3, in dark mode."

Under them: "Custom starts from the colorway you had picked. Button text switches between black and white to stay readable."

- Choosing Custom for the first time copies the colourway that was chosen into the four wells. After that, the custom colours are kept: switching to a preset and back to Custom brings back the owner's custom colours **(call)**.
- Colours are stored as sRGB; a colour picked in another colour space is converted.

**Preview** — two small panels side by side, labelled Light and Dark, each drawn in that mode with the chosen colours: the ring with digits, a Start focus button, − and +, the goal bar, a few Stats bars, a small break ring with a Start break button, a "Now" as the event list draws it, and a strip of menu bar with the timer as it looks during a break. It follows the choice live, including while a well is being changed. The "Now" and the menu bar strip are there so a colour too pale or too dark to read as text shows up here, not first during a real break (see section 4).

**UI spelling** — American ("Colorway", "Your colors"), as macOS and the owner write it **(call)**. Code comments keep the project's existing spelling.

### 4. Where the colours go

| Colour | Used for |
| --- | --- |
| Focus | Ring during focus and when focus is next · main buttons in focus phases (Start focus, Pause, Resume) · goal bar (Timer page and popover) · Stats bar chart and the selected-range outline · Stats calendar blocks · "Now" in the event list · Settings sidebar icons |
| Break | Ring during a break and when a break is next · main buttons in break phases (Start break, Pause, Resume) · menu bar countdown text and icon tint during a break |
| Text on a colour | Main-button text and Stats calendar block labels: white or near-black, whichever has more contrast against the colour, worked out per colour and per mode **(call)**. This replaces today's fixed white button text and `Theme.onFocus`. |

| Text in a colour | "Now" in the event list, today's date in the Stats month calendar, and the menu bar timer during a break are drawn in the colour itself. They use the colour exactly as picked, with no fallback **(call)**: the owner chose it, and the preview shows these before a real break does. A fallback rule would also have to leave today's amber menu bar timer (about 2.7:1 on a light menu bar) alone. |

Everything else keeps today's system colours. Today all of these read `Theme.focus` / `Theme.rest`; after this change they read the chosen colourway, and nothing in the app hard-codes the teal or amber any more.

### 5. A set focus length stays

A length set for the next focus session — by typing in the ring's digits or with − / + — stays as the focus length:

- through starting that session, cancelling it, ending it early, finishing it, the breaks after it, later cycles and new days;
- across quitting and relaunching the app.

It is replaced only when the owner sets a length again, or changes Focus in Settings → Cycle; then the Timer page shows the new default. Today's rule stays: a length set against one Focus default doesn't come back if the default is changed and changed back. Settings → Cycle keeps showing the default.

The length is stored with the app's other state; older saved data without it loads as "no length set" **(call: where it's stored is the builder's)**.

### 6. Room around the ring at every size

Today the ring's stroke is drawn centred on its edge, so half of it (about 16 pt at full-screen size) spills outside the ring's frame, and the gap under it is a fixed 22 pt.

- The stroke is drawn inside the ring's frame, so the frame is what you see.
- The gaps above and below the ring grow with the ring: 22 pt at the smallest ring sizes, proportionally more as it grows **(call: the exact rule is the builder's, as long as the next two hold)**.
- At every window size from 640 × 480 to full screen, with and without the event list, the visible gap between the ring and the phase label above it, and between the ring and the buttons below it, is at least 22 pt, and the column still fits in the window.

### 7. Event times as a range

Each row under the timer shows the event's start and end:

```
● 1:30–3:47 PM   Standup                 Now
● 4:00–4:30 PM   Design review
```

- The range uses the system's time-range format, so it follows the 12/24-hour setting ("13:30–15:47").
- A current event shows **Now** at the right, semibold, in the focus colour. Later events show nothing there.
- The title truncates in the middle, as today; the range never truncates.
- VoiceOver reads "1:30 to 3:47 PM, Standup, now".
- Events crossing midnight show their times without dates, as today (known limit).
- Row height is unchanged, so the Timer page still fits the same number of rows.

### 8. The new app icon

- `icon.svg` and `icon.png` are copied into `Resources/Icon/`; the originals in the project root stay where they are.
- `Resources/Icon/` and the root `icon.svg` are git-ignored, like `icon.png`.
- The icon script draws `Resources/Icon/icon.svg` with AppKit at every iconset size. The tile keeps its own rounded shape, sits on the macOS icon grid (824 px square centred on a 1024 px canvas) and gets a soft drop shadow that follows its outline. The PNG crop logic goes.
- The build script remakes the icon when the SVG or the icon script is newer than the built icon. `icon.png` is kept for reference and not used by the build.

## Checking it

- **Unit tests (core):** the eight presets and their values; Custom seeded from the chosen preset and kept after switching away; preferences falling back to defaults on unknown or damaged values; the black-or-white text choice (white on #336B82, near-black on #E9BA66); which controls go in which row for every state; the focus length staying through start, cancel, end early, finish, a break, a new day and a relaunch, and being replaced by a Settings change.
- **Self-check (app, fake data only):** Settings → Appearance renders with each mode; picking a preset recolours the ring and buttons; Custom shows the four wells and their text; the Timer page at 640 × 480 and at a large size has at least 22 pt between ring and label and between ring and buttons, and both button rows inside the window; the Cycle units end at the same x, just left of the steppers; event rows show a range and "Now". It must use its own preferences, never the owner's.
- **By hand (owner):** the real colour panel; System / Light / Dark against the real menu bar; the new icon in the Dock and Finder after `scripts/build-app.sh --install`.

## Left to the builder

- The exact gap-growth rule (section 6) and the button row heights.
- Where the focus length is stored, within the constraints above.
- The preview's exact contents and size, within section 3.
- The tile and well layout details, matching the approved mock.
- How the self-check isolates its preferences.
