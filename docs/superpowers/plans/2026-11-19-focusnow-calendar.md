# FocusNow Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings → Calendar, today's events under the timer, a Chart | Calendar switch in Stats, and a stable local signing certificate so calendar access survives reinstalls.

**Architecture:**
- **Core library (`FocusNowCore`).** Calendar reading sits behind a `CalendarSource` protocol. The library holds:
  - the fake source;
  - the pure logic: filtering upcoming events, the focus blocks, periods, hour span and month grid, and period text;
  - two `@Observable` stores: `CalendarPreferences` and `CalendarModel`.
  
  All of these are unit-tested with Swift Testing.
- **App target.** It holds the EventKit source, the SwiftUI views, and the wiring in `AppDelegate`. Self-check mode uses the fake source and never touches EventKit.

**Tech Stack:** Swift 6 package (tools 6.0), SwiftUI + AppKit, EventKit, Swift Charts, Swift Testing, bash and `security`/`codesign`/`openssl` for signing.

**Spec:** `docs/superpowers/specs/2026-11-19-focusnow-calendar-design.md` (it builds on the v1, timer-page and settings-tab specs in the same folder).

## Global Constraints

- **Platform:** macOS 14+, Apple frameworks only, no third-party dependencies.
- **Info.plist:** add `NSCalendarsFullAccessUsageDescription` = "FocusNow shows today's events under the timer."
- **Calendar access:** the app asks only from the Settings button, never at launch. Write-only access counts as not granted.
- **Storage:**
  - new preferences go under their own UserDefaults keys, never inside `TimerSettings`;
  - each one falls back to its default on its own;
  - no change to the session log or `SessionRecord`.
- **Self-check:**
  - it uses `FakeCalendarSource` only and runs only against `FOCUSNOW_DATA_DIR`;
  - it takes no intrusive actions: it never presses "Open Privacy & Security", activates other apps, or touches the login keychain or trust settings;
  - it never replaces `/Applications/FocusNow.app`.
- **Copy, exactly as written:**
  - "Allow Access…", "Open Privacy & Security";
  - "FocusNow can show your calendar events on the Timer page.", "Calendar access is off.", "Reading calendars on this Mac.";
  - "Show today's events on the Timer page";
  - "No calendars on this Mac. Add an account in the Calendar app.";
  - "Nothing else on your calendar today", "Show your calendar here";
  - "No title", "Now", "until …", "to …", "+N more";
  - "No focus sessions", "Chart", "Calendar".
- **Values:**
  - the Timer list shows at most 3 rows;
  - the join gap is under 15 minutes (900 s);
  - the hour span is at least 6 hours, with a 1-hour pad on each side;
  - a block runs from its start to start + `activeSeconds`, clipped at the midnight after its start.
- **Signing identity name:** "FocusNow Local Signing".
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A timed event in progress that started yesterday, or runs past midnight,** must list as "Now" today. Task 1: `overnightEventInProgressIsNow`.
2. **Access revoked or switched to write-only while the app runs:**
   - the Timer list falls back to "Show your calendar here";
   - Settings shows Open Privacy & Security;
   - nothing stale stays on screen.
   
   Task 3: `revokedAccessClearsEverything`. Tasks 6 and 7 add self-check lines.
3. **A very long event title at 640×480:** it stays on one line, the ring stays at least 120 pt, and nothing overlaps. Task 7: self-check lines for long-title row height and min-size frames.
4. **A day with more focus periods than its month cell fits** shows "+N" and doesn't spill into neighbouring cells. Task 8: a seeded 6-period day, read back through the cell's VoiceOver label, plus a screenshot.
5. **A calendar added after others were unticked** starts ticked and its events show. A hidden calendar that's deleted leaves nothing broken. Task 3: `newCalendarStartsShown`.

---

### Task 1: Calendar types, the fake source, and upcoming events

**Files:**
- Create: `Sources/FocusNowCore/CalendarSource.swift`, `Sources/FocusNowCore/UpcomingEvents.swift`
- Modify: `Tests/FocusNowCoreTests/TestSupport.swift` (add an `event(...)` helper)
- Test: `Tests/FocusNowCoreTests/UpcomingEventsTests.swift`

**Interfaces:**
- Produces (all `public`, with public memberwise inits):
  ```swift
  enum CalendarAccess: String, Sendable { case notAsked, granted, denied, writeOnly; var canRead: Bool }
  struct CalendarColor: Equatable, Sendable { var red, green, blue: Double }
  struct CalendarInfo: Equatable, Identifiable, Sendable { var id, title, account: String; var color: CalendarColor }
  struct CalendarEvent: Equatable, Identifiable, Sendable {
      var id, calendarID, title: String; var start, end: Date
      var isAllDay, isDeclined, isCancelled: Bool; var color: CalendarColor }
  struct CalendarGroup: Equatable, Sendable { var account: String; var calendars: [CalendarInfo] }
  @MainActor protocol CalendarSource: AnyObject {
      var access: CalendarAccess { get }
      func requestAccess() async -> CalendarAccess
      func calendars() -> [CalendarInfo]
      func events(in interval: DateInterval) -> [CalendarEvent]
      var onChange: (() -> Void)? { get set } }
  @MainActor final class FakeCalendarSource: CalendarSource {
      var access: CalendarAccess; var grantsOnRequest: Bool
      var calendarList: [CalendarInfo]; var eventList: [CalendarEvent]
      private(set) var requestCount: Int
      init(access: CalendarAccess = .notAsked, calendars: [CalendarInfo] = [], events: [CalendarEvent] = [], grantsOnRequest: Bool = true)
      func simulateChange() }   // calls onChange
  struct UpcomingRow: Equatable, Sendable { var event: CalendarEvent; var isNow: Bool }
  struct UpcomingList: Equatable, Sendable { var rows: [UpcomingRow]; var moreCount: Int
      static let empty: UpcomingList
      func trimmed(to count: Int) -> UpcomingList }   // keeps the first `count` rows; the rest add to moreCount
  enum UpcomingEvents {
      static let limit = 3
      static func list(_ events: [CalendarEvent], hidden: Set<String>, now: Date, calendar: Calendar, limit: Int = limit) -> UpcomingList
      static func nextChange(_ events: [CalendarEvent], hidden: Set<String>, now: Date, calendar: Calendar) -> Date }
  ```
- **The fake's behaviour:**
  - `requestAccess` adds 1 to `requestCount`. If the access was `.notAsked`, it becomes `.granted` or `.denied` according to `grantsOnRequest`. It returns the access.
  - `calendars()` and `events(in:)` return nothing unless `access == .granted`.
  - `events(in:)` returns the events that overlap the interval.
- **`list` keeps** events with:
  - `end > now`;
  - `start <` the start of tomorrow, using `calendar`;
  - `!isAllDay && !isDeclined && !isCancelled`;
  - a calendar that isn't hidden.
  
  It sorts by `(start, title)`, and sets `isNow = start <= now`.
- **`nextChange`** is the earliest kept start or end after `now`, and never later than the start of tomorrow.

- [ ] **Step 1: Write the failing tests.** Add to TestSupport:
  ```swift
  func event(_ id: String, _ start: String, _ end: String, calendar: String = "work", title: String? = nil,
             allDay: Bool = false, declined: Bool = false, cancelled: Bool = false) -> CalendarEvent
  ```
  The title defaults to `id`, and the colour is any fixed colour. Then write `UpcomingEventsTests`, with `now = date("2026-11-19T10:15:00Z")`, the `utc` calendar, and these events:

  | id | start (UTC) | end (UTC) | flags |
  | --- | --- | --- | --- |
  | overnight | 2026-11-18T22:00 | 2026-11-19T11:00 | |
  | standup | 2026-11-19T10:00 | 10:30 | |
  | review | 11:00 | 12:00 | |
  | oneonone | 14:00 | 14:30 | |
  | retro | 15:00 | 16:00 | |
  | late | 17:00 | 18:00 | |
  | ended | 08:00 | 09:00 | |
  | holiday | 2026-11-19T00:00 | 2026-11-20T00:00 | allDay |
  | declined | 13:00 | 13:30 | declined |
  | cancelled | 13:30 | 14:00 | cancelled |
  | tomorrow | 2026-11-20T09:00 | 10:00 | |
  | hidden | 12:30 | 13:00 | calendar "home" |

  ```swift
  @Test func listsTodaysRemainingTimedEventsInOrder() {   // hidden: ["home"], limit: 10
      #expect(list.rows.map(\.event.id) == ["overnight", "standup", "review", "oneonone", "retro", "late"])
      #expect(list.rows.map(\.isNow) == [true, true, false, false, false, false])
      #expect(list.moreCount == 0) }
  @Test func overnightEventInProgressIsNow()               // only "overnight": rows == [overnight], isNow == true
  @Test func hiddenCalendarsOnlyHideTheirOwn()             // hidden: [] → ids contain "hidden"
  @Test func capsAtThreeAndCountsTheRest() {               // default limit
      #expect(list.rows.count == 3); #expect(list.moreCount == 3)
      #expect(list.trimmed(to: 1) == UpcomingList(rows: [list.rows[0]], moreCount: 5))
      #expect(list.trimmed(to: 5) == list) }
  @Test func sameStartOrdersByTitle()                      // "B" and "A" both at 11:00 → ["A", "B"]
  @Test func endingNowIsGoneAndStartingNowIsNow()          // end == now → excluded; start == now → isNow
  @Test func nextChangeIsTheNextStartOrEndOrMidnight() {
      #expect(UpcomingEvents.nextChange(events, hidden: ["home"], now: now, calendar: utc) == date("2026-11-19T10:30:00Z"))
      #expect(UpcomingEvents.nextChange([], hidden: [], now: now, calendar: utc) == date("2026-11-20T00:00:00Z")) }
  ```
- [ ] **Step 2: Run the tests and watch them fail.** Run `swift test --filter UpcomingEventsTests`. Expected: a compile failure, because `UpcomingEvents` and `CalendarEvent` don't exist yet.
- [ ] **Step 3: Implement the two files** to the interfaces above.
- [ ] **Step 4: Run the tests and watch them pass.** Run `swift test --filter UpcomingEventsTests`, then `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: calendar types, fake source and upcoming-event rules`

### Task 2: Calendar preferences

**Files:**
- Create: `Sources/FocusNowCore/CalendarPreferences.swift`
- Test: `Tests/FocusNowCoreTests/CalendarPreferencesTests.swift`

**Interfaces:**
- Consumes: `StatsRange` (existing).
- Produces:
  ```swift
  public enum StatsDisplay: String, Sendable { case chart, calendar
      static func offersCalendar(for range: StatsRange) -> Bool      // day, week, month
      func showsCalendar(for range: StatsRange) -> Bool }            // self == .calendar && offersCalendar
  @MainActor @Observable public final class CalendarPreferences {
      static let showOnTimerPageKey = "calendar.showOnTimerPage"
      static let hiddenCalendarsKey = "calendar.hiddenCalendarIDs"
      static let statsDisplayKey = "stats.display"
      init(defaults: UserDefaults)
      var showOnTimerPage: Bool          // default true
      var hiddenCalendarIDs: Set<String> // default []
      var statsDisplay: StatsDisplay }   // default .chart
  ```
- **Storage:** each property writes through to its own key at once, as a plain Bool, string array and string. Each key loads with a type check, and falls back to its default when the stored value is missing or of the wrong type.

- [ ] **Step 1: Write the failing tests.**
  ```swift
  @Test func defaults()                              // true, [], .chart
  @Test func survivesANewInstanceOnTheSameDefaults()  // set false, ["work"], .calendar → new instance reads them
  @Test func existingTimerSettingsStillLoad() {
      // SettingsStore on `defaults` with focusMinutes = 50; then set every CalendarPreferences value;
      // a new SettingsStore on the same defaults → focusMinutes == 50 and goalHistory unchanged }
  @Test func aCorruptValueFallsBackAlone() {
      // defaults.set(42, forKey: hiddenCalendarsKey); defaults.set("bogus", forKey: statsDisplayKey);
      // defaults.set(false, forKey: showOnTimerPageKey)
      // → hiddenCalendarIDs == [], statsDisplay == .chart, showOnTimerPage == false }
  @Test func calendarIsOfferedForDayWeekMonthOnly() {
      #expect(StatsRange.allCases.filter { StatsDisplay.offersCalendar(for: $0) } == [.day, .week, .month])
      #expect(StatsDisplay.calendar.showsCalendar(for: .week))
      #expect(!StatsDisplay.calendar.showsCalendar(for: .year))
      #expect(!StatsDisplay.chart.showsCalendar(for: .day)) }
  ```
- [ ] **Step 2: Run the tests and watch them fail.** Run `swift test --filter CalendarPreferencesTests`. Expected: a compile failure.
- [ ] **Step 3: Implement `CalendarPreferences.swift`.**
- [ ] **Step 4: Run the tests and watch them pass.** Run `swift test --filter CalendarPreferencesTests`, then `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: calendar preferences under their own keys`

### Task 3: CalendarModel

**Files:**
- Create: `Sources/FocusNowCore/CalendarModel.swift`
- Test: `Tests/FocusNowCoreTests/CalendarModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces:
  ```swift
  @MainActor @Observable public final class CalendarModel {
      init(source: CalendarSource, preferences: CalendarPreferences, clock: @escaping () -> Date, calendar: Calendar)
      private(set) var access: CalendarAccess
      private(set) var groups: [CalendarGroup]      // by account, accounts and titles sorted case-insensitively
      private(set) var upcoming: UpcomingList       // UpcomingEvents.list(limit: 3)
      func isShown(_ calendarID: String) -> Bool
      func setShown(_ shown: Bool, calendarID: String)   // updates preferences.hiddenCalendarIDs, recomputes upcoming
      func refresh()          // re-reads access, calendars, today's events; recomputes nextChange
      func refreshIfDue()     // refresh() when clock() >= the stored nextChange
      func requestAccess() async }   // source.requestAccess(), then refresh()
  ```
- **What it does:**
  - `init` sets `source.onChange` to call `refresh()`, then calls `refresh()` itself.
  - It never calls `requestAccess` on its own.
  - When access isn't `.granted`, `groups == []` and `upcoming == .empty`.
  - Events come from `source.events(in:)` for today's interval in `calendar`.

- [ ] **Step 1: Write the failing tests.** Use `clock = FakeClock(date("2026-11-19T10:15:00Z"))`, preferences on `freshDefaults()`, and these calendars:
  - `work` "Work" (Google);
  - `home` "Home" (iCloud);
  - `birthdays` "Birthdays" (iCloud).
  
  And these events:
  - `standup` (work) 10:00–10:30;
  - `review` (work) 11:00–12:00;
  - `gym` (home) 18:00–19:00.
  
  ```swift
  @Test func notAskedShowsNothingAndNeverAsks()      // access .notAsked, groups [], upcoming .empty, fake.requestCount == 0
  @Test func grantingLoadsCalendarsGroupedByAccount() async {
      // await model.requestAccess()
      #expect(model.access == .granted)
      #expect(model.groups.map(\.account) == ["Google", "iCloud"])
      #expect(model.groups[1].calendars.map(\.title) == ["Birthdays", "Home"])
      #expect(model.upcoming.rows.map(\.event.id) == ["standup", "review", "gym"]) }
  @Test func refusingLeavesItOff() async             // grantsOnRequest false → .denied, groups []
  @Test func aCalendarChangeRefreshes()              // granted; append event "new" 13:00–13:30; simulateChange → ids contain "new"
  @Test func refreshIfDueDropsAnEndedEvent() {
      // granted; remove "review" from fake.eventList silently; clock 10:16; refreshIfDue → "review" still listed
      // clock 10:31; refreshIfDue → ids == ["gym"] }
  @Test func hidingACalendarPersistsAndFilters()     // setShown(false, "work") → prefs.hiddenCalendarIDs == ["work"], !isShown("work"), ids == ["gym"]
  @Test func newCalendarStartsShown()                // hide "work"; add calendar "new" + event; simulateChange → isShown("new"), its event listed;
                                                     // remove "work" from calendarList; simulateChange → no crash, groups lack "work"
  @Test func revokedAccessClearsEverything()         // granted; fake.access = .denied; simulateChange → .denied, groups [], upcoming .empty
  @Test func writeOnlyCannotRead()                   // fake .writeOnly → model.access == .writeOnly, !access.canRead, upcoming .empty
  @Test func aNewDayRefreshes()                      // granted; add event 2026-11-20T09:00–10:00 silently; clock 2026-11-20T08:00; refreshIfDue → listed
  ```
- [ ] **Step 2: Run the tests and watch them fail.** Run `swift test --filter CalendarModelTests`. Expected: a compile failure.
- [ ] **Step 3: Implement `CalendarModel.swift`.**
- [ ] **Step 4: Run the tests and watch them pass.** Run `swift test --filter CalendarModelTests`, then `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: calendar model with access, groups and upcoming events`

### Task 4: Focus blocks, periods, hour span, month grid, period text

**Files:**
- Create: `Sources/FocusNowCore/FocusCalendar.swift`
- Test: `Tests/FocusNowCoreTests/FocusCalendarTests.swift`, `Tests/FocusNowCoreTests/PeriodFormatTests.swift`

**Interfaces:**
- Consumes: `SessionRecord`.
- Produces:
  ```swift
  public struct FocusBlock: Equatable, Sendable { var sessionID: UUID; var start, end: Date; var startHour, endHour: Double }
  public struct FocusPeriod: Equatable, Sendable { var start, end: Date }
  public struct FocusDay: Equatable, Identifiable, Sendable {
      var day: DateInterval; var focusSeconds: Int; var blocks: [FocusBlock]; var periods: [FocusPeriod]; var id: Date { day.start } }
  public struct HourSpan: Equatable, Sendable { var first: Int; var last: Int }   // hours of the day, 0...24, first < last
  public struct FocusCalendar: Sendable {
      static let joinGap: TimeInterval = 900
      static let minimumHours = 6
      init(calendar: Calendar)
      func blocks(_ sessions: [SessionRecord]) -> [FocusBlock]          // focus kind only, sorted by start
      func periods(_ blocks: [FocusBlock]) -> [FocusPeriod]             // join when next.start - prev.end < joinGap
      func days(in interval: DateInterval, sessions: [SessionRecord]) -> [FocusDay]   // one per calendar day
      func hourSpan(_ blocks: [FocusBlock]) -> HourSpan?                // nil when empty
      func monthWeeks(_ month: DateInterval) -> [[Date?]] }             // rows of 7, first weekday per calendar
  public enum PeriodFormat { static func text(_ period: FocusPeriod, calendar: Calendar, uses24Hour: Bool) -> String }
  ```
- **Blocks:** a block ends at `min(start + activeSeconds, start of the next day)`. `startHour` and `endHour` are wall-clock hours from the calendar's hour, minute and second components, as fractional hours. An end at the next midnight is `24`.
- **Hour span:**
  - `first = max(0, floor(min startHour) - 1)`;
  - `last = min(24, ceil(max endHour) + 1)`;
  - if `last - first < 6`, raise `last` (up to 24) first, then lower `first`.
- **`days`:** groups blocks by start day; `focusSeconds` is the sum of `activeSeconds` for focus sessions started that day.
- **`monthWeeks`:** has as many rows as the month touches, 4–6. **Ruling:** the spec says "5–6", but a 28-day February that starts on the first weekday has 4.
- **Period text:**
  - en dash "–"; ":00" dropped;
  - 12-hour: lower-case "am" or "pm", shared only when both ends fall on the same day in the same half;
  - 24-hour: "HH:mm", and an end at midnight is "24:00".

- [ ] **Step 1: Write the failing tests.** Use the `utc` calendar unless noted. Add a helper `session(start:active:endedAt:)`.
  ```swift
  @Test func blockRunsForTheFocusedTime()   // 2026-11-19T17:30, active 1200, endedAt 2026-11-20T08:00 → end 17:50, startHour 17.5, endHour ≈ 17.8333
  @Test func blocksClipAtMidnight()         // 23:30, active 3600 → end 2026-11-20T00:00, endHour 24
  @Test func breaksAreNotBlocks()           // rest(...) sessions → no blocks
  @Test func periodsJoinGapsUnder15Minutes() // blocks 10:00–10:40, 10:45–11:25, 11:40–12:20 → periods [10:00–11:25, 11:40–12:20]
  @Test func hourSpanPadsAnHourAndKeepsSix() {
      // 10:00–10:40 → HourSpan(first: 9, last: 15); 08:10 and a block ending 17:20 → (7, 19)
      // 00:20–01:00 → (0, 6); 22:00–23:00 → (18, 24); 23:30 clipped to 24 → (18, 24) }
  @Test func emptyHasNoSpan()               // hourSpan([]) == nil
  @Test func clockChangeDayUsesWallClock()  // America/New_York; 2026-03-08 10:00 local (14:00Z), active 2400 → startHour 10.0, endHour ≈ 10.6667
  @Test func daysTotalAndSplitPerDay()      // week of 2026-11-16 with the StatsViewModelTests fixture → 7 days, totals [7200, 7200, 5000, 3900, 0, 0, 0]
  @Test func monthWeeksFollowTheFirstWeekday() {
      // utc (Monday first), Nov 2026 → 6 rows; row 0 == [nil×6, Nov 1]; row 5 == [Nov 30, nil×6]
      // Dec 2026 → 5 rows; Feb 2027 → 4 rows; Sunday-first calendar, Nov 2026 → 5 rows, row 0 starts Nov 1 }
  // PeriodFormatTests (12-hour unless noted):
  // 10:00–11:50 "10–11:50 am"; 11:30–13:00 "11:30 am–1 pm"; 16:00–19:00 "4–7 pm"; 10:00–12:00 "10 am–12 pm";
  // 23:00–24:00 "11 pm–12 am"; 00:30–01:00 "12:30–1 am";
  // 24-hour: 10:00–11:50 "10:00–11:50"; 16:00–19:00 "16:00–19:00"; 23:00–24:00 "23:00–24:00"
  ```
- [ ] **Step 2: Run the tests and watch them fail.** Run `swift test --filter "FocusCalendarTests|PeriodFormatTests"`. Expected: a compile failure.
- [ ] **Step 3: Implement `FocusCalendar.swift`.**
- [ ] **Step 4: Run the tests and watch them pass.** Run the same filter, then `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: focus blocks, periods, hour span and month grid`

### Task 5: Stats model exposes the calendar data

**Files:**
- Modify: `Sources/FocusNowCore/StatsViewModel.swift`
- Test: `Tests/FocusNowCoreTests/StatsViewModelTests.swift`

**Interfaces:**
- Consumes: `FocusCalendar`, `FocusDay`, `HourSpan` (Task 4).
- Produces, on `StatsViewModel`:
  ```swift
  public private(set) var focusDays: [FocusDay]     // the interval's days for day/week/month; [] for year/allTime
  public private(set) var hourSpan: HourSpan?       // over all of focusDays' blocks; nil when none or year/allTime
  public private(set) var monthWeeks: [[Date?]]     // month range only; [] otherwise
  ```
  They're computed in `reload()` from `intervalSessions`, so paging and range changes keep them in sync.

- [ ] **Step 1: Write the failing tests** against the existing fixture (now 2026-11-19T12:00Z, week from Nov 16).
  ```swift
  @Test func weekHasSevenFocusDays() {
      #expect(model.focusDays.map(\.focusSeconds) == [7200, 7200, 5000, 3900, 0, 0, 0])
      #expect(model.focusDays[3].blocks.count == 2)
      #expect(model.hourSpan == HourSpan(first: 8, last: 16)) }
  @Test func dayHasOneFocusDay() {   // range = .day
      #expect(model.focusDays.count == 1)
      #expect(model.focusDays[0].periods.count == 2)          // 09:00–09:40 and 10:00–10:25: a 20-minute gap
      #expect(model.hourSpan == HourSpan(first: 8, last: 14)) }
  @Test func monthHasDaysAndWeeks()  // range = .month → focusDays.count == 30, monthWeeks.count == 6
  @Test func yearAndAllTimeHaveNone() // focusDays == [], hourSpan == nil, monthWeeks == []
  @Test func pagingKeepsThemInSync() // week pageBack → focusDays[0].day.start == 2026-11-09, totals [0, 1800, 0, 0, 0, 0, 0]
  ```
- [ ] **Step 2: Run the tests and watch them fail.** Run `swift test --filter StatsViewModelTests`. Expected: a compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests and watch them pass.** Run `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: stats model exposes focus days, hour span and month weeks`

### Task 6: EventKit source, wiring, Info.plist, Settings → Calendar

**Files:**
- Create: `Sources/FocusNow/EventKitCalendarSource.swift`, `Sources/FocusNow/CalendarSettingsPane.swift`, `Sources/FocusNow/SelfCheckCalendar.swift`
- Modify: `Sources/FocusNow/AppDelegate.swift`, `Sources/FocusNow/SettingsView.swift`, `Sources/FocusNow/MainWindowView.swift`, `Sources/FocusNow/SelfCheck.swift`, `Resources/Info.plist`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `final class EventKitCalendarSource: CalendarSource`, `@MainActor`, with one `EKEventStore`;
  - on `AppDelegate`: `private(set) var calendarPrefs: CalendarPreferences!`, `calendarSource: CalendarSource!`, `calendarModel: CalendarModel!`, and `func showCalendarSettings()` (page `.settings`, section `.calendar`, show the main window);
  - `SettingsSection.calendar`, titled "Calendar", with symbol `calendar`, after General;
  - `struct CalendarPane: View` built as `CalendarPane(model: CalendarModel, preferences: CalendarPreferences)`. `SettingsView` and `MainWindowView` take `calendarModel` and `calendarPrefs`;
  - `func checkCalendar(_ snap: DebugSnapshots) async` in `SelfCheckCalendar.swift`. The new self-check phase is `"calendar"`; add it to the default list right after `"settings"`.
- **The EventKit source:**
  - **Access mapping:** `.fullAccess`/`.authorized` → `.granted`; `.writeOnly` → `.writeOnly`; `.denied`/`.restricted` → `.denied`; `.notDetermined` → `.notAsked`.
  - **Requests:** `requestFullAccessToEvents`, through a continuation if Swift 6 objects to sending the store. After a grant, call `store.reset()` before reading.
  - **Event fields:**
    - event `id` = `eventIdentifier` + start time, because recurring events share an identifier;
    - declined = the attendee with `isCurrentUser` has `participantStatus == .declined`;
    - cancelled = `status == .canceled`;
    - colour = the calendar's `cgColor` converted to sRGB;
    - account = `calendar.source.title`.
  - **Changes:** `onChange` fires on `.EKEventStoreChanged`.
- **AppDelegate wiring:**
  - `FakeCalendarSource()` when `DebugSnapshots.directory != nil`, otherwise `EventKitCalendarSource()`;
  - a 15-second repeating timer calls `calendarModel.refreshIfDue()`;
  - `NSApplication.didBecomeActiveNotification` and the existing day-change observer call `calendarModel.refresh()`.
- **The pane:** follows the spec's Settings → Calendar section, with the same grouped-Form look as the other panes. Its parts:
  - an access section with the copy for each state;
  - the Timer-page switch, bound to `preferences.showOnTimerPage`;
  - one `Section` per `CalendarGroup`, headed by the account. Each calendar is a `Toggle`, styled as a checkbox, with its colour dot, bound through `isShown`/`setShown`.
  
  Allow Access… calls `Task { await model.requestAccess() }`. Open Privacy & Security opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`.
- **Persist note:** add `statsDisplay=\(calendarPrefs.statsDisplay)` to the persist phase's note.

- [ ] **Step 1: Write the failing self-check.** `checkCalendar` seeds the fake with:
  - the calendars Work (Google), Home (iCloud) and Birthdays (iCloud);
  - one event in progress: Standup, from 10 minutes ago to 20 minutes from now;
  - four more events spread evenly between now and midnight, so the check works at any hour. One has a 120-character title.
  
  It shows Settings → Calendar, then logs:
  ```
  calendar source=fake access=notAsked allow=<Allow Access… present> requests=0 (want fake notAsked true 0)
  after Allow: access=granted requests=1 groups=2 toggles=<checkboxes> (want granted 1 2 3)
  untick Work: hidden=["work"] (want ["work"])        // accessibility press on the "Work" checkbox
  denied: privacy=<Open Privacy & Security present> groups=0 (want true 0)
  writeOnly: privacy=true groups=0 (want true 0)
  ```
  It also logs `voiceover:` lines for the pane, and takes the screenshots `settings-calendar`, `settings-calendar-dark` and `settings-calendar-denied`. It leaves the fake granted with Work ticked again for Task 7.
- [ ] **Step 2: Run it and watch it fail.** Run `swift build`. Expected: a compile failure, because `calendarModel` and `SettingsSection.calendar` are missing.
- [ ] **Step 3: Implement** the EventKit source, wiring, Info.plist key, section and pane.
- [ ] **Step 4: Run it and watch it pass.**
  - Run `scripts/self-check.sh calendar`, then `scripts/self-check.sh settings`. Expected: every `want` matches. The settings phase is unchanged, apart from its sidebar now having 4 rows.
  - Check the screenshots by eye.
  - Run `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: Settings → Calendar with EventKit access and calendar choice`

### Task 7: Today's events on the Timer page

**Files:**
- Create: `Sources/FocusNow/UpcomingEventsView.swift`
- Modify: `Sources/FocusNow/TimerPageView.swift`, `Sources/FocusNow/MainWindowView.swift`, `Sources/FocusNow/TimerParts.swift` (accessibility identifier `today-bar` on `TodayBar`), `Sources/FocusNow/SelfCheckCalendar.swift`

**Interfaces:**
- Consumes: `CalendarModel.upcoming`/`access`, `CalendarPreferences.showOnTimerPage`, `UpcomingList.trimmed(to:)`, `AppDelegate.showCalendarSettings()`.
- Produces:
  - `struct UpcomingEventsView: View`, built as `UpcomingEventsView(model: CalendarModel, rowLimit: Int, onSetUp: () -> Void)`, with accessibility identifier `upcoming-events`;
  - `enum TimerPageLayout { static func rows(for size: CGSize) -> Int; static func diameter(for size: CGSize, eventRows: Int, hasMore: Bool, showsEvents: Bool) -> CGFloat }`. With no events, `diameter` is today's `min(min(w,h)*0.7, h - 170)`. With events, it also subtracts the events section's height. `rows(for:)` is the largest row count from 1 to 3 that keeps the diameter at least 120.
  - `TimerPageView` takes `calendarModel`, `calendarPrefs` and `onShowCalendarSettings`.
- **Rows:**
  - a colour dot, then the time column: "Now", or the start time with `.dateTime.hour().minute()`;
  - the title, on one line, truncated in the middle; an empty title shows "No title";
  - the trailing text: "until <end>" for Now, otherwise "to <end>";
  - VoiceOver reads each row as one element, "Now, Standup, until 10:30".
- **The "+N more" line** is plain secondary text.
- **When access isn't granted,** the section shows only the "Show your calendar here" link button, which calls `onSetUp`.

- [ ] **Step 1: Write the failing self-check,** extending `checkCalendar` on the Timer page at 760×560 with the fake granted.
  ```
  timer events: rows=3 first="Now, Standup, until …" more=<n> (want 3 Now >0)
  hidden Work: rows exclude work events=true (want true)
  long title row height=<h> others=<h> (want equal)
  switch off: section=false ringBigger=true (want false true)
  nothing left: text="Nothing else on your calendar today" (want present)      // fake events all ended
  not granted: link=true → after press page=settings section=calendar (want true settings calendar)
  min size 640×480: rows=<r> diameter=<d> (want ≥1 ≥120) todayBar.maxY<=events.minY=true events inside window=true
  ```
  Take the screenshots `timer-events`, `timer-events-dark` and `timer-events-min`.
- [ ] **Step 2: Run it and watch it fail.** Run `swift build`. Expected: a compile failure, because `UpcomingEventsView` and `TimerPageLayout` are missing.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run it and watch it pass.**
  - Run `scripts/self-check.sh calendar,timer`. Expected: every `want` matches, and the existing timer lines are unchanged.
  - Check the screenshots by eye.
  - Run `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: today's calendar events under the timer`

### Task 8: Stats Chart | Calendar

**Files:**
- Create: `Sources/FocusNow/FocusCalendarView.swift`
- Modify: `Sources/FocusNow/StatsView.swift`, `Sources/FocusNow/MainWindowView.swift`, `Sources/FocusNow/SelfCheck.swift` (make `seedHistory` internal), `Sources/FocusNow/SelfCheckCalendar.swift`

**Interfaces:**
- Consumes: `StatsViewModel.focusDays`/`hourSpan`/`monthWeeks`, `CalendarPreferences.statsDisplay`, `StatsDisplay.showsCalendar(for:)`, `PeriodFormat.text`.
- Produces:
  - `StatsView(model: StatsViewModel, preferences: CalendarPreferences)`;
  - `struct FocusCalendarView: View`, built as `FocusCalendarView(model: StatsViewModel, uses24Hour: Bool)`. `uses24Hour` comes from `DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)` not containing "a".
- **The switch:**
  - It's a segmented `Picker` labelled "Stats view", with segments "Chart" and "Calendar".
  - It sits at the right end of the header, and shows only when `StatsDisplay.offersCalendar(for: model.range)`.
  - When `preferences.statsDisplay.showsCalendar(for: model.range)`, `FocusCalendarView` replaces the chart and the session list.
- **Today and This week:**
  - Swift Charts `RectangleMark`s. x is the day, as a categorical label; y runs from `startHour` to `endHour`.
  - The y scale is reversed, so morning is at the top, over `hourSpan.first...hourSpan.last`.
  - In the week view, the x labels sit at the top, reading "Mon 17 · 2h 40m".
  - Labels inside blocks are the builder's call.
  - With no blocks, the view shows "No focus sessions".
- **This month:**
  - a grid with a weekday header from `calendar.shortWeekdaySymbols`, rotated to `firstWeekday`;
  - each cell shows the date, the total, and as many `PeriodFormat` lines as fit, then "+N";
  - each cell's VoiceOver label: "<date>, <total>, <periods joined by ", ">".

- [ ] **Step 1: Write the failing self-check,** extending `checkCalendar`.
  - **Seeding:** seed history if the store is empty. Also seed 6 sessions of 20 minutes on the day 3 days ago, an hour apart, so that day has 6 periods.
  - **Logs:**
  ```
  stats switch: day=true week=true month=true year=false allTime=false (want true true true false false)
  calendar week: days=7 blocks=<n> span=<first>–<last> (want 7, n = sum of focusDays blocks, span = model.hourSpan)
  calendar month: busy day label="<…, +N…>" (want "+" present)
  empty day: "No focus sessions" present=true (want true)     // page back on .day until a day has no blocks, at most 14
  chart again: chart present=true (want true)
  ```
  - **Screenshots:** `stats-calendar-day`, `stats-calendar-week`, `stats-calendar-week-dark` and `stats-calendar-month`. Render each through `snap.render(StatsView(model:preferences:))` at 760×560, plus `stats-calendar-month-min` at 640×480.
  - **Afterwards:** reset `statsDisplay` to `.chart` so the stats phase is unchanged.
- [ ] **Step 2: Run it and watch it fail.** Run `swift build`. Expected: a compile failure, because `StatsView` has no `preferences` and `FocusCalendarView` is missing.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run it and watch it pass.**
  - Run `scripts/self-check.sh calendar,stats`. Expected: every `want` matches, and the stats lines are unchanged.
  - Check the screenshots by eye, light and dark.
  - Run `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: Chart | Calendar switch in Stats`

### Task 9: Local signing certificate

**Files:**
- Create: `scripts/make-signing-cert.sh`, `scripts/check-signing.sh`
- Modify: `scripts/build-app.sh`

**Interfaces:**
- `scripts/make-signing-cert.sh [keychain]`:
  - **Arguments and inputs:** the keychain defaults to the login keychain. It reads `FOCUSNOW_KEYCHAIN_PASSWORD` when set; without it, `security` asks in the terminal.
  - **If the identity exists:** when "FocusNow Local Signing" is already in that keychain, it prints that and exits 0.
  - **Creating the certificate:** a self-signed certificate valid for 10 years, with `extendedKeyUsage=codeSigning`, through `openssl`. Use a config file if `-addext` isn't supported.
  - **Importing it:** the certificate and key are imported as a `.p12`, compatible with macOS, with `-T /usr/bin/codesign`. Then `security set-key-partition-list -S apple-tool:,apple:,codesign: -s`, so builds don't prompt.
- `scripts/build-app.sh`:
  - it signs with "FocusNow Local Signing" when `security find-identity -p codesigning ${FOCUSNOW_SIGNING_KEYCHAIN:-}` lists it, and passes `--keychain` when that variable is set;
  - otherwise it signs ad hoc;
  - it prints `signed with FocusNow Local Signing` or `signed ad hoc`.
- `scripts/check-signing.sh`:
  - it creates a throwaway keychain under `build/signing-check.noindex`, with a known password, and doesn't add it to the search list;
  - it runs `make-signing-cert.sh` against it, then `FOCUSNOW_SIGNING_KEYCHAIN=… scripts/build-app.sh`;
  - it prints `codesign -d -r-` and `codesign --verify --strict` for the app, and asserts the designated requirement mentions `certificate` and not `cdhash`;
  - it deletes the keychain;
  - it exits non-zero on failure.

- [ ] **Step 1: Write the failing check.** Write `scripts/check-signing.sh`.
- [ ] **Step 2: Run it and watch it fail.** Run `scripts/check-signing.sh`. Expected: it fails, because `make-signing-cert.sh` doesn't exist.
- [ ] **Step 3: Implement** `make-signing-cert.sh` and the `build-app.sh` change.
  - **The trust experiment:** if codesign refuses an untrusted identity, or the requirement isn't certificate-based, apply the spec's ruling:
    - `make-signing-cert.sh` adds `security add-trusted-cert -p codeSign` only for the login keychain;
    - the check stops short of trust and prints `trust: hand check`;
    - record the result in the ledger.
  - **No prompts:** watch for any GUI keychain prompt during the check. One showing up is a failure.
- [ ] **Step 4: Run it and watch it pass.**
  - Run `scripts/check-signing.sh`. Expected: it ends with `designated requirement names the certificate: ok`, and the throwaway keychain is gone.
  - Run `scripts/build-app.sh`. Expected: `signed ad hoc`, because the owner hasn't run the script yet.
  - Run `swift test`. Expected: all tests pass.
- [ ] **Step 5: Commit.** `feat: optional local signing certificate so permissions survive rebuilds`

---

**After the last task:** run the full `scripts/self-check.sh`. Then run the final whole-branch review, and finish the branch. The owner's hand checks:
- run `scripts/make-signing-cert.sh`, then install;
- the real permission prompt;
- real calendars and events appear;
- access survives a second install;
- notifications and launch at login still work.
