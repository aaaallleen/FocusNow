import Foundation
import Observation

public struct TimerSettings: Equatable, Codable, Sendable {
    public var focusMinutes = 40
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var sessionsBeforeLongBreak = 4
    public var dailyGoalSeconds = 14_400
    public var soundOn = true

    public init() {}

    public static let minuteRange = 1...180
    public static let sessionsRange = 1...12
    public static let goalRange = 900...57_600

    /// The same settings with every value forced into its allowed range.
    public func clamped() -> TimerSettings {
        var s = self
        s.focusMinutes = s.focusMinutes.clamped(to: Self.minuteRange)
        s.shortBreakMinutes = s.shortBreakMinutes.clamped(to: Self.minuteRange)
        s.longBreakMinutes = s.longBreakMinutes.clamped(to: Self.minuteRange)
        s.sessionsBeforeLongBreak = s.sessionsBeforeLongBreak.clamped(to: Self.sessionsRange)
        s.dailyGoalSeconds = s.dailyGoalSeconds.clamped(to: Self.goalRange)
        return s
    }

    public func plannedSeconds(for kind: SessionKind) -> Int {
        switch kind {
        case .focus: focusMinutes * 60
        case .shortBreak: shortBreakMinutes * 60
        case .longBreak: longBreakMinutes * 60
        }
    }
}

/// A daily goal that applies from `day` (start of a local day) onward.
public struct GoalChange: Codable, Equatable, Sendable {
    public var day: Date
    public var seconds: Int

    public init(day: Date, seconds: Int) {
        self.day = day
        self.seconds = seconds
    }
}

@MainActor @Observable
public final class SettingsStore {
    private static let settingsKey = "settings"
    private static let goalHistoryKey = "goalHistory"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar

    private var current: TimerSettings

    /// Every write is clamped to the allowed ranges and persisted at once.
    public var settings: TimerSettings {
        get { current }
        set {
            let old = current
            let clamped = newValue.clamped()
            current = clamped
            persist(clamped, forKey: Self.settingsKey)
            if clamped.dailyGoalSeconds != old.dailyGoalSeconds {
                recordGoal(clamped.dailyGoalSeconds)
            }
        }
    }

    public private(set) var goalHistory: [GoalChange]

    public init(defaults: UserDefaults, clock: @escaping () -> Date, calendar: Calendar) {
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        let loaded = Self.load(TimerSettings.self, forKey: Self.settingsKey, from: defaults)?.clamped()
            ?? TimerSettings()
        self.current = loaded
        var history = Self.load([GoalChange].self, forKey: Self.goalHistoryKey, from: defaults) ?? []
        if history.isEmpty {
            // The goal before any recorded change applies to every earlier day.
            history = [GoalChange(day: .distantPast, seconds: loaded.dailyGoalSeconds)]
            self.goalHistory = history
            persist(history, forKey: Self.goalHistoryKey)
        } else {
            self.goalHistory = history.sorted { $0.day < $1.day }
        }
    }

    /// The goal that was in force on the local day containing `day`.
    public func goal(on day: Date) -> Int {
        let start = calendar.startOfDay(for: day)
        return goalHistory.last(where: { $0.day <= start })?.seconds
            ?? goalHistory.first?.seconds
            ?? settings.dailyGoalSeconds
    }

    private func recordGoal(_ seconds: Int) {
        let today = calendar.startOfDay(for: clock())
        goalHistory.removeAll { $0.day == today }
        goalHistory.append(GoalChange(day: today, seconds: seconds))
        goalHistory.sort { $0.day < $1.day }
        persist(goalHistory, forKey: Self.goalHistoryKey)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
