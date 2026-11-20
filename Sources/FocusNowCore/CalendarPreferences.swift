import Foundation
import Observation

/// What the Stats page shows for Today, This week and This month.
public enum StatsDisplay: String, Sendable {
    case chart, calendar

    /// Year and All time only ever show the chart.
    public static func offersCalendar(for range: StatsRange) -> Bool {
        range == .day || range == .week || range == .month
    }

    public func showsCalendar(for range: StatsRange) -> Bool {
        self == .calendar && Self.offersCalendar(for: range)
    }
}

/// The calendar's preferences and the Stats view choice.
///
/// Each value has its own UserDefaults key, apart from `TimerSettings`: that
/// struct decodes as a whole, so a key it didn't know would make saved
/// settings fail to load and fall back to defaults. A value stored with the
/// wrong type falls back to its own default and leaves the others alone.
@MainActor @Observable
public final class CalendarPreferences {
    public static let showOnTimerPageKey = "calendar.showOnTimerPage"
    public static let hiddenCalendarsKey = "calendar.hiddenCalendarIDs"
    public static let statsDisplayKey = "stats.display"

    @ObservationIgnored private let defaults: UserDefaults

    /// "Show today's events on the Timer page".
    public var showOnTimerPage: Bool {
        didSet { defaults.set(showOnTimerPage, forKey: Self.showOnTimerPageKey) }
    }

    /// The calendars the owner unticked; calendars added later start shown.
    public var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(hiddenCalendarIDs.sorted(), forKey: Self.hiddenCalendarsKey) }
    }

    public var statsDisplay: StatsDisplay {
        didSet { defaults.set(statsDisplay.rawValue, forKey: Self.statsDisplayKey) }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        showOnTimerPage = defaults.object(forKey: Self.showOnTimerPageKey) as? Bool ?? true
        hiddenCalendarIDs = Set(defaults.object(forKey: Self.hiddenCalendarsKey) as? [String] ?? [])
        statsDisplay = (defaults.object(forKey: Self.statsDisplayKey) as? String).flatMap(StatsDisplay.init) ?? .chart
    }
}
