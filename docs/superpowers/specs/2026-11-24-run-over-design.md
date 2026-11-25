# Allow time to run over: design

A short design for a small change. Flowtime (no set lengths) is a separate piece of work that comes after this one.

## Why

Pomodoro's fixed schedule is the right default, but it sometimes stops the owner in the middle of a long, focused stretch. The owner wants to choose to keep going when that happens, and have the extra time count as focus, without leaving the fixed schedule for good.

## What it does

- **The setting.** Settings → Cycle gets a new section with a switch, **Allow time to run over**, off by default. It has this caption: "When a focus reaches zero, the clock keeps counting up until you start your break. The extra time counts as focus. It stops after 10 minutes without keyboard or mouse use."
- **Focus only.** Breaks already "run over": after a break the app waits for Start focus.
- **At zero, with the switch on:**
  - What happens today still happens: the Glass sound plays, the popover opens and the menu bar icon flashes.
  - The focus session keeps running and counts up, shown as `+4:12`. That's the countdown format with a `+` in front, so `+1:02:03` past an hour.
  - The `+` time shows in the menu bar, the popover ring and the Timer page ring. The ring stays full, and the phase label stays `FOCUS · 2 of 4`.
- **The buttons during the extra time:**

  | State | Main button | Others |
  |---|---|---|
  | Counting up | Start break | Pause, Skip break |
  | Paused while counting up | Resume | Start break, Skip break |

- **What each button does:**
  - **Start break:** ends the focus and starts the break straight away. The break is short or long, as the cycle says.
  - **Skip break:** ends the focus and skips that break. The app then waits with the next focus ready to start.
  - **Pause / Resume:** as today. Paused time doesn't count.
- **The 10-minute idle stop.** The check runs only while counting up and running; a paused session isn't checked.
  - **When it triggers:** after 10 minutes with no keyboard or mouse input, the focus ends at the owner's last input. It never ends before the original zero.
  - **Afterwards:** the app is in today's "focus finished" state: the break is pending, Start break / Skip break are shown, and the icon flashes until answered.
  - **No second sound:** the sound already played at zero.
- **How it's saved.** One finished focus (`completed`) whose active time is the whole session, with the extra time included. It counts in Stats, toward the daily goal, and as one of the 4 before the long break. Its planned length stays the original one.
- **Turning the switch off or on applies from the next time a focus reaches zero.** A session that's already counting up carries on until it ends. This matches how the length settings apply from the next session.
- **Unchanged:** with the switch off, everything works exactly as today.

## Smaller calls (mine; change any of them)

- **The flash and the popover:** clicking back into your work counts as answering.
  - The popover that opens at zero closes on a click elsewhere or on Escape, and that click also stops the flash.
  - The `+m:ss` time then stays in the menu bar without flashing.
  - Today a popover opened by a finish stays until you use it. With the switch on, carrying on working is a legitimate answer, so a click elsewhere counts.
- **The notification text at zero, with the switch on:** "Focus time is up". Body: "The clock keeps running until you start your break." With the switch off it's unchanged.
- **Sleep:** the Mac sleeping, or 30 seconds without a tick, pauses the session as today, extra time included. While running over, the pause is taken at the last keyboard or mouse input, never before zero. So when the Mac sleeps from idleness before the 10-minute stop, the idle minutes don't count. (Added after the final review: the original line counted them.)
- **Relaunch:** the app never resumes a session after a relaunch. It logs the session up to its last 15-second checkpoint and ends it. A session counting up gets the same treatment, logged as a finished focus with its extra time up to that checkpoint, with no flash or sound afterwards. (Corrected while planning: the approved draft said it "carries on", which isn't how relaunch works today.)

## Approaches considered

- **The timer keeps the focus running past zero (chosen).**
  - The engine treats reaching zero as "time's up" rather than the end, and the session ends on Start break, Skip break or the idle stop.
  - The result is one record and a correct cycle position, and the existing snapshot gives crash recovery.
- **End the session at zero and run a separate stopwatch for the extra time.** Rejected:
  - It gives two Stats entries, or rewrites the first one.
  - The cycle moves on to the break while you're still focusing.
  - The extra time is lost if the app quits.
- **A "Keep going" button at zero instead of a setting.** The owner chose a setting.

## Constraints for the builder

- **Settings are stored as one JSON value** (`TimerSettings`, in `SettingsStore`). With the current synthesized `Codable`, adding a field would make saved settings fail to decode, and every existing owner's settings would reset to the defaults. The new field must decode as `false` when it's missing.
- **The engine's time all comes from injected functions** (`clock`, `settings`). Idle time must come in the same way, for example `idleSeconds: () -> TimeInterval`, so unit tests can drive it.
  - In the app it reads `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`. The `~0` is `kCGAnyInputEventType`; `.null` would be a different event type. It needs no permission.
- **`finish(_:outcome:at:notify:)` clamps active time to the planned length.** A session that ran over must keep its full active time.
- **The self-check must not open permission prompts or activate other apps.** Its idle time must be faked.

## Tests

- **Unit tests (FocusNowCore), test-first:**
  - Reaching zero with the switch on keeps the session running, sets `needsAttention`, and calls the finish callback once.
  - Remaining time goes below zero.
  - Start break and Skip break end the session with its full active time and advance the cycle.
  - The idle stop ends at the last input and never before the original zero.
  - Paused time doesn't count.
  - The switch off behaves as today.
  - Old saved settings without the new field load with every other value intact.
- **Self-check:** a short focus with the switch on.
  - It reaches zero, counts up, and shows `+` in the menu bar and the popover.
  - Start break logs one session with the extra time in it.
  - Faked idle ends the focus at the last input.
  - The Settings switch appears in Cycle and turns the setting on.

## Not in this change

- Flowtime, which comes next.
- Breaks that count up.
- Auto-starting the next session.
- Editing past sessions.
