import Foundation
import Observation

/// Everything the stats window shows: the five tiles, the chart for the
/// selected range and period, and the session list under it.
@MainActor @Observable
public final class StatsViewModel {
    public struct Tile: Equatable, Sendable {
        public var focusSeconds: Int
        public var sessionCount: Int

        public init(focusSeconds: Int, sessionCount: Int) {
            self.focusSeconds = focusSeconds
            self.sessionCount = sessionCount
        }
    }

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let goal: (Date) -> Int
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let calc: StatsCalculator
    @ObservationIgnored private let focusCalendar: FocusCalendar
    /// A date inside the period being shown.
    @ObservationIgnored private var anchor: Date
    /// True while showing the period containing now; then each reload moves
    /// with the clock (a new day or week). Paging back stops following.
    @ObservationIgnored private var followsNow = true
    @ObservationIgnored private var intervalSessions: [SessionRecord] = []

    private var currentRange: StatsRange = .week
    private var currentSelection: Date?

    public private(set) var interval: DateInterval
    public private(set) var tiles: [StatsRange: Tile] = [:]
    public private(set) var buckets: [StatsBucket] = []
    public private(set) var summary = StatsSummary(dailyAverageSeconds: 0, goalMetDays: 0, elapsedDays: 0)
    public private(set) var listInterval: DateInterval
    public private(set) var listedSessions: [SessionRecord] = []
    public private(set) var todayGoalSeconds = 0
    /// The Stats calendar's days for Today, This week and This month; empty for Year and All time.
    public private(set) var focusDays: [FocusDay] = []
    /// The hours the Today and This week calendars show; nil with no focus to show.
    public private(set) var hourSpan: HourSpan?
    /// This month's days in rows of seven; empty for other ranges.
    public private(set) var monthWeeks: [[Date?]] = []

    public init(sessions: SessionStore, goal: @escaping (Date) -> Int,
                clock: @escaping () -> Date, calendar: Calendar) {
        self.store = sessions
        self.goal = goal
        self.clock = clock
        self.calendar = calendar
        self.calc = StatsCalculator(calendar: calendar)
        self.focusCalendar = FocusCalendar(calendar: calendar)
        let now = clock()
        self.anchor = now
        self.interval = DateInterval(start: now, duration: 0)
        self.listInterval = DateInterval(start: now, duration: 0)
        reload()
    }

    /// Changing the range returns to the period containing now and clears the selection.
    public var range: StatsRange {
        get { currentRange }
        set {
            currentRange = newValue
            anchor = clock()
            followsNow = true
            currentSelection = nil
            reload()
        }
    }

    /// The chart bar whose sessions the list shows; nil shows the default day.
    public var selectedBucketID: Date? {
        get { currentSelection }
        set {
            currentSelection = newValue
            updateList()
        }
    }

    public var canPageBack: Bool { currentRange != .allTime }

    public var canPageForward: Bool { currentRange != .allTime && interval.end <= clock() }

    public func pageBack() {
        guard canPageBack, let component = pageComponent,
              let earlier = calendar.date(byAdding: component, value: -1, to: interval.start) else { return }
        anchor = earlier
        followsNow = false
        currentSelection = nil
        reload()
    }

    public func pageForward() {
        guard canPageForward else { return }
        anchor = interval.end
        currentSelection = nil
        reload()
        if interval.start <= clock() && clock() < interval.end { followsNow = true }
    }

    /// Re-reads the store and the clock. Call when the window appears and after a session is saved.
    public func reload() {
        let now = clock()
        let earliest = store.earliestStart()
        todayGoalSeconds = goal(now)

        var newTiles: [StatsRange: Tile] = [:]
        for range in StatsRange.allCases {
            let sessions = store.sessions(in: calc.interval(for: range, containing: now, earliest: earliest))
            newTiles[range] = Tile(focusSeconds: calc.focusSeconds(sessions), sessionCount: calc.focusCount(sessions))
        }
        tiles = newTiles

        if followsNow { anchor = now }
        let newInterval = calc.interval(for: currentRange, containing: anchor, earliest: earliest)
        if newInterval != interval { currentSelection = nil }
        interval = newInterval
        intervalSessions = store.sessions(in: interval)
        buckets = calc.buckets(for: currentRange, interval: interval, sessions: intervalSessions, goal: goal)
        summary = calc.summary(interval: interval, sessions: intervalSessions, today: now, goal: goal)
        updateCalendar()
        updateList()
    }

    // MARK: - Private

    private var pageComponent: Calendar.Component? {
        switch currentRange {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .allTime: nil
        }
    }

    private func updateCalendar() {
        guard StatsDisplay.offersCalendar(for: currentRange) else {
            focusDays = []
            hourSpan = nil
            monthWeeks = []
            return
        }
        focusDays = focusCalendar.days(in: interval, sessions: intervalSessions)
        hourSpan = focusCalendar.hourSpan(focusDays.flatMap(\.blocks))
        monthWeeks = currentRange == .month ? focusCalendar.monthWeeks(interval) : []
    }

    private func updateList() {
        let focus = intervalSessions.filter { $0.kind == .focus }
        let now = clock()
        let day: DateInterval
        if let id = currentSelection, let bucket = buckets.first(where: { $0.id == id }) {
            day = bucket.interval
        } else if interval.start <= now && now < interval.end {
            day = calendar.dateInterval(of: .day, for: now)!
        } else if let last = focus.last {
            day = calendar.dateInterval(of: .day, for: last.startedAt)!
        } else {
            listInterval = interval
            listedSessions = []
            return
        }
        listInterval = day
        listedSessions = focus.filter { $0.startedAt >= day.start && $0.startedAt < day.end }
    }
}
