# Flow: design

A focus with no set length: it counts up from 00:00 until the owner stops it. It's chosen with a Focus | Flow switch at the top of the timer. There's no timed break afterwards; the rest between flows is the owner's own. It builds on "Allow time to run over" (branch `feat/run-over`, PR #7) and reuses its counting-up machinery.

## Why

Some work is better done without a fixed schedule. The owner wants to start, keep going as long as the work flows, and stop, with the time counting as focus. Rest between flows doesn't need timing. Run-over covers "this one Pomodoro ran long". Flow is for choosing an open-ended session from the start, and the owner usually does flow by itself rather than mixed into a Pomodoro cycle.

## Goals

- **Choosing:** pick Focus or Flow from a switch at the top of the popover and the Timer page, before starting.
- **A flow:** counts up from 00:00 with no end. It's stopped by the owner, or by the 10-minute idle stop. It's saved as focus: it counts in Stats and the daily goal, and is listed as "flow".
- **Always moving:** the ring fills once an hour, then fills again over itself in a second colour.

## Non-goals

- Timing or saving the break between flows. (The owner: "we don't need to time the flow break's time, we only need to start/stop a flow".)
- Suggested break lengths.
- Sounds or notifications during flow. Nothing reaches zero.
- Flow counting toward the Pomodoro cycle.
- Changing the Settings page. Flow has no settings.

## Anti-goals (a failure even if it works)

- **Time away counting as focus.** The idle stop and sleep trimming from run-over must apply to a flow.
- **The ring or buttons jumping when the switch changes.**
- **Flow disturbing the Pomodoro cycle.** A flow never changes "2 of 4", a pending break, the long break, or the day the cycle belongs to.
- **Changing anything for owners who never touch the switch.** With Focus chosen, every Pomodoro state looks and works as today, apart from the switch at the top.

## What the owner sees

### The switch and the row under it

- **The switch:** a two-segment switch, `Focus | Flow`, is the first thing in the popover and on the Timer page. It takes the phase label's place.
- **The row under it:**
  - **Focus chosen:** shows the rest of today's phase label: `1 OF 4` before and during a focus, and `BREAK` / `LONG BREAK` for a Pomodoro break.
  - **Flow chosen:** blank.
  - **Its height is reserved in every state**, so nothing moves when the switch changes.
- **When it can be changed:** only while idle with a focus next. During any session, a Pomodoro break, or a pending break (including a finished focus waiting for its break) it's dimmed and locked. VoiceOver reads it as disabled.
- **Memory:** it remembers the last choice, including after a relaunch.

### States (light-mode mockups: `.superpowers/brainstorm/…/flow-layout.html`; approved with changes: no text under the switch in Flow; second colour A; the flow-break panel is dropped)

| State | Under the switch | Ring | Digits | Main button | Others |
|---|---|---|---|---|---|
| Idle, Focus chosen | `1 OF 4` | empty | `40:00` (the set length) | Start focus | − / + |
| Idle, Flow chosen | blank | empty | `00:00` | Start flow | none (the row's space is kept, empty) |
| Flowing | blank | laps (below) | `52:10` counting up, no `+` | Stop | Pause |
| Flowing, paused | blank | laps, frozen | frozen | Resume | Stop |

### The ring

- **The laps:** the ring fills once an hour in the focus colour. In the second hour a deeper shade of the focus colour fills over the full first ring. The third hour fills in the focus colour over the second, and so on, alternating.
- **Paused:** the ring and digits freeze.

### The menu bar

- **Flowing:** the hourglass icon and the time counting up, `52:10`, then `1:24:30` past an hour.
- **Paused:** the pause icon, as today.
- **Stopped:** idle, as today: the icon alone.

### What each button does

- **Start flow:** starts a flow from 00:00.
- **Stop:** ends the flow and saves it. The app goes back to idle with Flow still chosen.
- **Pause / Resume:** as today. Paused time doesn't count.

### How a flow ends on its own

These are the same rules as run-over, already built in `feat/run-over`:
- **10 minutes without keyboard or mouse input:** it ends at the last input, never before it started, and is saved. The app goes back to idle with Flow still chosen. There's no sound and no flash: the menu bar no longer counting is the sign.
- **The Mac sleeping, or a tick gap over 30 s:** pauses it at the last input, and Resume or Stop follows.
- **Quitting** (⌘Q, logging out, restarting): saves it.
- **A crash, then a relaunch:** saves it up to the last 15-second checkpoint.

### How it's saved

- **The record:** a focus record with `plannedSeconds == 0`. That marks it as flow; no other session has a zero planned length, because the minimum is 1 minute. Its outcome is `completed` and its active time is the whole flow. It counts in Stats totals, the goal and the calendar.
- **The Stats session list** shows it as `52m flow` instead of `52m focus`.
- **Under a minute:** a flow that ends with less than a minute of active time isn't saved, the same rule as a Pomodoro ended early.
- **The cycle isn't touched:**
  - no `cyclePosition` change and no long break;
  - `nextKind` stays `focus`;
  - `cycleDay` and `lastFinishAt` aren't updated, so a new day still resets the Pomodoro cycle as usual.

## Approaches considered

- **A flow is a focus that's "past zero" from its first second (chosen).**
  - It's an `ActiveSession` with `plannedSeconds == 0` and `timeUpAt == startedAt`. Run-over's code then counts it up, idle-stops it, trims sleep, saves it on quit and recovers it after a crash.
  - **New work:**
    - the label without `+`;
    - keeping it out of the cycle;
    - ending at Stop or the idle stop without a pending break;
    - the controls for flow;
    - the switch;
    - the ring laps;
    - the "flow" label in Stats.
  - **Chosen because** it reuses the paths most likely to go wrong (idle, sleep, quit, crash), which PR #7 just tested and reviewed.
- **A separate session style.** A `.flow` style stored on `ActiveSession` and `SessionRecord`, with its own engine paths. The names would be clearer, but it means:
  - duplicating the counting, idle, sleep, quit and crash logic;
  - changing the saved session format (a SwiftData schema change).
- **A stopwatch in the app, outside the timer engine.** Rejected: it wouldn't be saved or recovered, and Stats and the goal wouldn't see it.

The owner picked the switch on the timer (per-session choice) over a mode in Settings, and keeping flow outside the cycle. The owner handed the build approach to the designer, who picked the first approach. After the builder check, the owner dropped the timed flow break.

## Designer's calls (the owner can change any)

- **Flow ignores "Allow time to run over".** It works the same whether that switch is on or off.
- **Stop is the main button while flowing, with Pause beneath it.** Stop is how a flow normally ends; Pause covers interruptions.
- **The idle stop doesn't flash the icon,** unlike a finished Pomodoro, because there's nothing waiting to be answered.
- **The second shade** is worked out from the focus colour, so custom colourways get one too. It goes lighter where darker wouldn't show.

## Constraints for the builder

- **This builds on `feat/run-over`, which isn't merged yet.** It relies on:
  - `ActiveSession.timeUpAt`, `TimerEngine.isRunningOver`, `overtimeSeconds`, `clockLabel`;
  - the idle stop (`runOverIdleLimitSeconds`, `idleSeconds`) and `endRunOver()`;
  - sleep trimming in `pause(asOf:)`, and `prepareForQuit()`.
- **Run-over code that needs care for flow:**
  - **`finish` advances the cycle and sets `cycleDay` / `lastFinishAt`.** A flow must not.
  - **The idle stop sets `needsAttention`, and `start()` / `skipBreak()` end a run-over into its break.** A flow ends into idle with no attention.
  - **`clockLabel` adds `+`.** A flow must not.
  - **The zero branch in `tick()`** must never fire for a flow. With `timeUpAt` set at the start it doesn't, but test it.
  - **`controls`** returns the run-over controls whenever `isRunningOver`. A flow needs its own (Stop and Pause, or Resume and Stop).
  - **Crash recovery** (`recover(from:)`) of a flow must save it as `completed` up to the checkpoint, and leave the cycle alone.
- **Saved state must stay compatible.** The remembered switch choice is new timer state, so it must be optional or decode with a default, as `focusOverride` and `timeUpAt` do. There's no change to the saved session format; flow is marked by `plannedSeconds == 0`.
- **Timer page layout:** the switch plus its row is taller than the phase label it replaces. The Timer page's layout maths (`TimerPageLayout`) and the self-check's `gaps …` and `zoom …` lines must be updated so the ring still fits at every window size the self-check tries, and nothing overlaps at 640×480.
- **The self-check** must not open permission prompts or activate other apps, and must fake idle time, as in `checkRunOver`.
- **Copy:**
  - The switch segments: `Focus` and `Flow`.
  - New buttons: `Start flow` and `Stop`.
  - The Stats row: `<duration> flow`.

## Left to the builder

- The exact second shade, within "clearly visible against the focus colour in both light and dark mode".
- Where the remembered switch choice lives. It's timer state, so the engine snapshot is the natural home.
- New `TimerControl` cases (for example `.startFlow`, `.stop`), and how `controlRows` places them per the table.
- The switch's control (a SwiftUI segmented `Picker` or a custom one), as long as VoiceOver reads it as one control with two choices and as disabled while locked.

## Tests

- **Engine unit tests:**
  - **Starting and counting:** Start flow counts up from 0 with no `+`.
  - **Stop:** saves a focus with `plannedSeconds == 0`, completed, with its full time, and returns to idle.
  - **Short or away:** under a minute isn't saved. The idle stop ends it at the last input, with no sound, no attention, and back to idle. Sleep pauses it at the last input.
  - **Ending without Stop:** quitting saves it as completed. Crash recovery saves it as completed up to the checkpoint.
  - **The cycle and the zero branch:** a flow never changes "n of 4", `nextKind`, the long break or the cycle's day. The zero branch never fires.
  - **The switch:** it's locked except while idle with a focus next, and its choice survives a relaunch. Old timer state without the new field still loads.
  - **Controls:** the table's buttons for each state.
- **Self-check:**
  - **The switch:** on the popover and the Timer page, in both choices. Nothing moves when it changes, and it's locked while flowing.
  - **A short flow:** the menu bar and ring count up with no `+`. Stop saves it and the Stats row reads "flow".
  - **Faked idle time:** the idle stop.
  - **The ring's second hour:** shows the second colour, using a long flow with a faked clock if needed.
  - **Layout:** the Timer page's `gaps` and `zoom` lines still pass at every size.
