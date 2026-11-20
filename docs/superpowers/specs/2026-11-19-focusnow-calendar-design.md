# FocusNow: Calendar

Builds on v1 (`2026-11-19-focusnow-v1-design.md`), the Timer page (`2026-11-19-focusnow-timer-page-design.md`) and the Settings tab (`2026-11-19-focusnow-settings-tab-design.md`). Those still bind where this one is silent.

Items marked **(call)** were decided by Claude, not by the owner. Everything else was decided by the owner in conversation.

## Why

- **See when you focused, not just how much.** Stats shows totals and bars per hour or day. The owner wants a calendar view of when the focus actually happened: "10–12 am, 4–7 pm".
- **See what's coming up while at the timer.** v1 planned the calendar phase so focus can work around meetings. Today's upcoming events sit under the timer.
- **Configure it in one place.** Settings gets a Calendar section, as the Settings-tab design anticipated.

## Goals

1. **Settings → Calendar:** calendar access, which calendars count, and a switch for the Timer page list.
2. **Timer page:** today's upcoming events, under the timer.
3. **Stats:** a **Chart | Calendar** switch for Today, This week and This month. Calendar draws when each focus session happened.
4. **Signing:** calendar access survives reinstalls.

## Non-goals

- Google Calendar sign-in. It comes after EventKit, as v1 planned.
- Meetings or breaks in the Stats calendar. Focus sessions only.
- Recording pauses. The owner: "only need to draw out focus time, no need to record pauses otherwise it makes the calendar view very obstructed". No change to the session data.
- A calendar view for This year and All time.
- Events in the popover **(call)**: it stays small.
- Creating, editing or opening events **(call)**.
- Planning a day's schedule (v1's phase 1).

## Anti-goals

- Tests or the self-check reading the owner's real calendar, or showing the calendar permission prompt.
- Asking for calendar access at launch, or at any moment other than the owner pressing a button.
- A cluttered calendar view.
- Existing settings lost or reset when the new preferences are added.
- Any change to focus totals, tiles, goal history or the session log.

## Constraints

- Apple frameworks only: EventKit, Swift Charts, SwiftUI, AppKit.
- macOS 14+. Calendar access uses the macOS 14 full-access request. Info.plist needs `NSCalendarsFullAccessUsageDescription` **(call: copy is "FocusNow shows today's events under the timer.")**.
- The app is not sandboxed and has no hardened runtime, so no entitlements are needed.
- Standing rules for this machine: the self-check runs only against `FOCUSNOW_DATA_DIR`, takes no intrusive actions, and never replaces the installed app.

## Approaches

| Question | Options | Picked |
| --- | --- | --- |
| How to draw Today and This week | **Swift Charts**: rectangles on an hours axis, built-in axes and VoiceOver, matches the bar chart. **Hand-drawn grid**: full control over labels, but more code and manual accessibility and hit-testing. | Swift Charts (owner) |
| Where calendars come from | **EventKit**: calendars added to the Calendar app on this Mac. **Google sign-in**: direct, more work. | EventKit, as v1 planned |
| What a focus block spans | **Start to end** of the session, pauses included: a session left paused overnight draws to midnight. **Each running stretch**, which needs pauses recorded. **Start plus time focused**: the block is as long as the focus. | Start plus time focused (owner) |
| Where the Stats calendar sits | **A Chart \| Calendar switch.** **Replace the chart and list** for those ranges. | The switch (owner: "also") |
| Signing | **A local signing certificate**, created once. **Ad-hoc signing as now**, re-prompting after each install. | Local certificate (owner) |

## Design

### Reading calendars

- **One small interface, two versions.**
  - The real version uses one EventKit store for the app's lifetime.
  - A fake version holds made-up calendars and events.
  - Unit tests and the self-check use only the fake. In self-check mode the app never touches EventKit.
- **The interface provides:**
  - the access state: not asked, granted, denied, or write-only;
  - a request for access;
  - the calendars: an ID, title, colour and account name for each;
  - events in a time range: ID, calendar ID, title, start, end, all-day flag, whether the owner declined, and whether it's cancelled;
  - a notice when the calendar database changes.
- **Write-only access** (macOS 14's "add events only") can't read events, so it counts as not granted **(call)**.
- **Where the logic lives:** the core library holds the filtering, grouping and layout logic, with unit tests, like the existing stats code. The app target holds EventKit and the views.

### Settings → Calendar

The sidebar reads **Cycle, Goal, General, Calendar**, with a calendar icon.

```
┌─────────────┬────────────────────────────────────────────┐
│ ⟳ Cycle     │  Calendar access                           │
│ ◎ Goal      │  Reading calendars on this Mac.            │
│ ⚙ General   │                                            │
│ ▦ Calendar  │  Show today's events on the Timer page [●] │
│             │                                            │
│             │  iCloud                                    │
│             │   [✓] ● Home                               │
│             │   [ ] ● Birthdays                          │
│             │  Google (work)                             │
│             │   [✓] ● Work                               │
└─────────────┴────────────────────────────────────────────┘
```

- **Access, by state:**
  - **Not asked:** "FocusNow can show your calendar events on the Timer page." and an **Allow Access…** button. The system prompt appears only when the owner presses it.
  - **Denied, restricted or write-only:** "Calendar access is off." and an **Open Privacy & Security** button. It opens the Calendars privacy pane.
  - **Granted:** "Reading calendars on this Mac." with no button.
  - The pane updates when access changes. Returning from System Settings counts **(call)**.
- **Show today's events on the Timer page:** a switch, on by default **(call)**.
- **Calendars:** shown only when access is granted.
  - Every calendar on this Mac appears, grouped under its account name, each with its colour and a checkbox.
  - All are ticked at first.
  - FocusNow stores the *unticked* calendars, so calendars added later start ticked **(call)**.
  - The list updates when calendars are added or removed.
  - With no calendars: "No calendars on this Mac. Add an account in the Calendar app." **(call)**.
- **Storage (call):**
  - **Where:** the calendar preferences (the switch and the unticked calendars) and the Stats view choice go under their own UserDefaults keys, not inside `TimerSettings`.
  - **Why:** `TimerSettings` decodes with Swift's synthesized `Codable`, which fails on saved data missing a new key, and a failed decode resets every setting to its default.
  - **Errors:** each new value loads with a fallback to its default, without affecting the others.

### Timer page: today's events

```
          FOCUS · 2 of 4
           (  32:10  )
   [ Pause ] [ End early ] [ Cancel ]
   Today 2h 40m  ▓▓▓▓▓░░░  of 4h
   ────────────────────────────────
   ● Now     Standup          until 10:30
   ● 11:00   Design review    to 12:00
   ● 2:00    1:1              to 2:30
     +2 more
```

- **Placement:** under today's progress bar, the same width (max 320 pt), after a hairline. The ring shrinks to make room. Its minimum stays 120 pt.
- **Which events:**
  - today's events (the local day) from ticked calendars, whose end is after now;
  - all-day, declined and cancelled events are left out **(call for cancelled)**;
  - order is by start time, then title.
- **Rows:**
  - up to 3 **(call)**, then a "+N more" line, which isn't clickable;
  - each row has the calendar's colour dot, then a time column and the title on one line, truncated;
  - the time column reads "Now" for an event in progress, ending "until 10:30"; otherwise the start time, ending "to 12:00";
  - times follow the system's 12/24-hour setting;
  - an empty title shows "No title" **(call)**;
  - overlapping events each get a row.
- **Other states:**
  - **Nothing left today:** "Nothing else on your calendar today".
  - **Access not granted:** a "Show your calendar here" link that opens Settings → Calendar.
  - **Switch off:** no section at all, so the ring gets the room.
- **Updates:**
  - when the calendar database changes;
  - when the Settings ticks or the switch change;
  - at midnight;
  - when a listed event starts or ends, within a minute **(call)**.
- **Small windows:** at the minimum window size (640×480) nothing overlaps and the ring stays at least 120 pt. If height runs short, fewer rows show, down to one plus "+N more" **(call)**.
- **VoiceOver** reads each row as one element, e.g. "Now, Standup, until 10:30".

### Stats: Chart | Calendar

- **The switch:**
  - It's a two-segment control, **Chart | Calendar**, in the Stats header row.
  - It shows only for Today, This week and This month. Year and All time always show the chart, as now.
  - One choice covers all three ranges and is remembered across launches **(call)**.
  - Moving to Year and back keeps the choice.
- **Calendar mode:**
  - It takes the space of the chart and the session list.
  - Unchanged: the tiles, period title, arrows, paging and summary text.
  - Bar selection doesn't apply in this mode.
- **What's drawn:**
  - finished focus sessions in the period, the same sessions the stats count;
  - each block starts when the session started and is as long as its focused time (`activeSeconds`), not its end time (owner). A session paused partway ends a little early on the calendar, and one left paused over sleep can't stretch the view;
  - ended-early sessions look the same **(call)**;
  - the session in progress isn't drawn, matching the totals **(call)**.
- **Midnight:**
  - a session belongs to the day it started on (v1 rule);
  - one that crosses midnight is drawn on its start day, clipped at midnight **(call)**.

**Today:**
- **Layout:** one column. Hours run down the side, with morning at the top.
- **Blocks:** one per session, in the focus colour. Breaks between sessions show as gaps.
- **Labels:** each block is labelled "10:00–10:40" when it fits. A shorter block shows just its start time, or no label. VoiceOver always reads the full time.

**This week:**
- **Layout:** seven day columns sharing the hours axis. The first weekday follows the system setting, as the chart does.
- **Column headers:** weekday, date and that day's total, e.g. "Mon 17 · 2h 40m".
- **Days:** future days and days without focus are empty columns.

```
           Mon 2h40   Tue 3h20   Wed 1h20
   9 am    ▇▇▇▇▇▇
  10 am    ▇▇▇▇▇▇     ▇▇▇▇▇▇
  11 am               ▇▇▇▇▇▇     ▇▇▇▇▇▇
   …
   4 pm    ▇▇▇▇▇▇
```

**Hours shown (Today and This week):**
- From the hour before the earliest block start to the hour after the latest block end in the period.
- At least 6 hours **(call)**, so one session isn't a full-height block.
- With no sessions, the view shows "No focus sessions" **(call)**.
- Clock-change days (23 or 25 hours) place blocks by their wall-clock time.

**This month:**
- **Grid:** a month grid. The first weekday follows the system setting. A weekday header row is followed by 5–6 week rows. Days outside the month are blank.
- **Each day cell:** the date, the day's total when there is one, and the day's focus periods as text, e.g. "10–12 am", "4–7 pm". If they don't all fit, the cell shows as many as fit and then "+N".
- **Periods:**
  - Consecutive focus sessions on the same day join into one period when the gap between one's end and the next one's start is under 15 minutes.
  - A period runs from its first block's start to its last block's end. Gaps are measured between block ends and starts.
- **Period text:**
  - exact minutes, with ":00" dropped and am/pm shared when both ends match, e.g. "10–11:50 am", "11:30 am–1 pm", "4–7 pm";
  - a period across noon reads "10 am–12 pm", and one clipped at midnight ends "12 am" **(call)**: the owner's "10–12 am" was a casual example, and standard usage reads "12 am" as midnight;
  - with the system on 24-hour time: "10:00–11:50" **(call)**.

### Signing

- **The script:** `scripts/make-signing-cert.sh` creates a self-signed code-signing identity named **FocusNow Local Signing** in the login keychain.
  - If the identity already exists, it does nothing.
  - The owner runs it. macOS may ask for the login password.
  - It takes an optional keychain path, so it can be tested against a throwaway keychain.
  - **Trust (call):** first check whether an untrusted self-signed identity signs and gives a designated requirement that names the certificate.
    - If it does, the script adds no trust setting.
    - If trust is needed, the script adds it when the owner runs it. Trust settings live in the owner's trust store, not the throwaway keychain, so the automated test stops short of trust, and that part becomes a hand check.
- **The build:** `scripts/build-app.sh` signs with that identity when it exists, otherwise ad hoc as now, and prints which one it used.
- **The point:** with the certificate, the app's designated requirement names the certificate, not the binary's hash, so macOS's permission grants survive rebuilds.
- **The first signed install** looks like a new app to macOS, so calendar access is asked for once more after it.

## Testing

**Unit tests (core):**
- **Upcoming events:**
  - leaves out ended, all-day, declined and cancelled events, and unticked calendars;
  - marks the event in progress as "Now";
  - orders the events, including overlaps;
  - caps the list and counts "+N more";
  - works across the day boundary.
- **Blocks:** a paused session's block is its start plus its focused time, not its end time.
- **Periods:** gaps under 15 minutes join and 15 minutes or more split; blocks crossing midnight are clipped.
- **Hours shown:** the 6-hour minimum; the empty period; clock-change days.
- **Month grid:** the first weekday and the 5- or 6-row months.
- **Period text:** 12-hour and 24-hour formatting.
- **Preferences:**
  - they persist and are remembered;
  - saved `TimerSettings` from before this change still load unchanged;
  - a corrupt preference value falls back to its default without resetting the others.

**Self-check (fake calendar, scratch data dir):**
- **Settings → Calendar:** shows each access state; unticking a calendar removes its events from the Timer page; the switch removes the section.
- **Timer page:** the list shows the "Now" row and "+N more". At 640×480 nothing overlaps and the ring is at least 120 pt.
- **Stats:**
  - the switch shows for Today, This week and This month, and is hidden for Year and All time;
  - the choice survives a relaunch;
  - blocks and month periods match seeded sessions;
  - screenshots in light and dark.
- **Signing script:** tested against a throwaway keychain; the signed app's designated requirement names the certificate.

**Hand checks for the owner:**
- the real permission prompt;
- real calendars and events appear;
- access survives a reinstall after the certificate is in place;
- notifications and launch at login still work after the first signed install.

## Left to the builder

- **Code:** names and types, and how often the Timer list refreshes (within the rules above).
- **Charts:** styling and label fitting.
- **Layout:** where the switch sits in the header, and the details of each month cell.
- **Icons.**
- **Signing script:** how it creates the certificate (`openssl` plus `security import`, or `certtool`).
