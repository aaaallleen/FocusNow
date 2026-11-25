import Foundation
import Observation

/// The focus/break timer. All time comes from the injected clock; the app calls
/// `tick()` a couple of times a second and the engine works out the rest.
@MainActor @Observable
public final class TimerEngine {
    public enum Status: Equatable, Sendable { case idle, running, paused }

    public static let minimumLoggedFocusSeconds = 60
    /// A longer silence between ticks while running is treated as blank time.
    public static let blankGapSeconds: TimeInterval = 30
    /// How often a running session is checkpointed for crash recovery.
    public static let snapshotIntervalSeconds: TimeInterval = 15
    /// A new day starts a fresh cycle, unless the last session ended less than this long ago
    /// (so a break earned just before midnight survives it).
    public static let dayRolloverGraceSeconds: TimeInterval = 3600
    /// A focus running over ends after this long without keyboard or mouse input.
    public static let runOverIdleLimitSeconds: TimeInterval = 600

    @ObservationIgnored private let settings: () -> TimerSettings
    /// Seconds since the owner last used the keyboard or mouse.
    @ObservationIgnored private let idleSeconds: () -> TimeInterval
    @ObservationIgnored private let sessions: SessionStore
    @ObservationIgnored private let snapshots: SnapshotStore
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// Called when a countdown reaches zero (not when a session is ended early).
    @ObservationIgnored public var onFinish: ((SessionKind) -> Void)?

    public private(set) var status: Status = .idle
    public private(set) var active: ActiveSession?
    /// What `start()` will begin.
    public private(set) var nextKind: SessionKind = .focus
    /// True from a countdown reaching zero until the owner responds.
    public private(set) var needsAttention = false
    /// Focus sessions done in the current cycle.
    public private(set) var cyclePosition = 0
    public private(set) var now: Date
    /// A focus length set on the timer. It stays, through sessions, breaks,
    /// days and relaunches, until it's set again. It belongs to the Focus
    /// default it was set against: once that default changes it reads as nil,
    /// and `focusDefaultChanged()` (or the next tick) drops it for good.
    public var nextFocusSecondsOverride: Int? {
        get {
            guard let focusOverride, focusOverride.focusMinutes == settings().focusMinutes else { return nil }
            return focusOverride.seconds
        }
        set { focusOverride = newValue.map { FocusOverride(seconds: $0, focusMinutes: settings().focusMinutes) } }
    }
    private var focusOverride: FocusOverride?
    /// Increments every time a session record is saved.
    public private(set) var savedSessionCount = 0

    @ObservationIgnored private var todayCache: (day: Date, seconds: Int)?
    /// The local day of the cycle's most recent activity; a new day starts a new cycle.
    @ObservationIgnored private var cycleDay: Date
    /// When the engine last heard from the app (a tick or an action).
    @ObservationIgnored private var lastSeen: Date
    @ObservationIgnored private var lastSnapshotAt: Date?
    @ObservationIgnored private var lastFinishAt: Date?

    public init(
        settings: @escaping () -> TimerSettings, sessions: SessionStore,
        snapshots: SnapshotStore, clock: @escaping () -> Date, calendar: Calendar,
        idleSeconds: @escaping () -> TimeInterval = { 0 }
    ) {
        self.settings = settings
        self.idleSeconds = idleSeconds
        self.sessions = sessions
        self.snapshots = snapshots
        self.clock = clock
        self.calendar = calendar
        let launchedAt = clock()
        self.now = launchedAt
        self.lastSeen = launchedAt
        self.cycleDay = calendar.startOfDay(for: launchedAt)
        recover(from: snapshots.load())
    }

    // MARK: - Derived values

    var currentSettings: TimerSettings { settings() }

    public var plannedSecondsForNext: Int {
        if nextKind == .focus, let override = nextFocusSecondsOverride { return override }
        return settings().plannedSeconds(for: nextKind)
    }

    /// Whole seconds left, rounded up. When idle, the length of the next session.
    public var remainingSeconds: Int {
        guard let active else { return plannedSecondsForNext }
        let left = TimeInterval(active.plannedSeconds) - active.activeSeconds(at: now)
        return max(0, Int(left.rounded(.up)))
    }

    /// A focus past zero that keeps counting up until the owner ends it.
    public var isRunningOver: Bool { active?.timeUpAt != nil }

    /// Whole active seconds past zero, rounded down; 0 unless running over.
    public var overtimeSeconds: Int {
        guard let active, active.timeUpAt != nil else { return 0 }
        return max(0, Int((active.activeSeconds(at: now) - TimeInterval(active.plannedSeconds)).rounded(.down)))
    }

    /// 0...1 through the active session; 0 when idle.
    public var progress: Double {
        guard let active, active.plannedSeconds > 0 else { return 0 }
        return min(1, active.activeSeconds(at: now) / TimeInterval(active.plannedSeconds))
    }

    /// Focus time stored for today plus the running focus session.
    public func todayFocusSeconds() -> Int {
        let day = calendar.startOfDay(for: now)
        let stored: Int
        if let cache = todayCache, cache.day == day {
            stored = cache.seconds
        } else {
            let interval = calendar.dateInterval(of: .day, for: now)!
            stored = sessions.sessions(in: interval)
                .filter { $0.kind == .focus }
                .reduce(0) { $0 + $1.activeSeconds }
            todayCache = (day, stored)
        }
        guard let active, active.kind == .focus, calendar.startOfDay(for: active.startedAt) == day else {
            return stored
        }
        return stored + Int(active.activeSeconds(at: now).rounded(.down))
    }

    // MARK: - Actions

    /// Starts the next session. While a focus runs over (Start break), ends it
    /// first, with all its time, and starts the break.
    public func start() {
        refreshNow()
        endRunOver()
        guard status == .idle else { return }
        rollOverDayIfNeeded()
        cycleDay = calendar.startOfDay(for: now)
        let planned = plannedSecondsForNext
        active = ActiveSession(kind: nextKind, startedAt: now, plannedSeconds: planned, lastResumedAt: now)
        status = .running
        needsAttention = false
        saveSnapshot()
    }

    public func pause() {
        refreshNow()
        pause(asOf: now)
    }

    public func resume() {
        refreshNow()
        guard status == .paused, var session = active else { return }
        session.lastResumedAt = now
        active = session
        status = .running
        saveSnapshot()
    }

    public func endEarly() {
        refreshNow()
        guard status != .idle, let session = active else { return }
        finish(session, outcome: .endedEarly, at: now)
    }

    public func cancel() {
        refreshNow()
        guard status != .idle else { return }
        active = nil
        status = .idle
        saveSnapshot()
    }

    /// Ends a running or paused break (logging its active time), or skips a
    /// pending break before it starts. While a focus runs over, ends it (with
    /// all its time) and skips the break after it. Otherwise does nothing when
    /// focus is current or next.
    public func skipBreak() {
        refreshNow()
        endRunOver()
        if let session = active {
            guard session.kind.isBreak else { return }
            finish(session, outcome: .endedEarly, at: now)
        } else {
            guard nextKind.isBreak else { return }
            advanceCycle(after: nextKind)
            saveSnapshot()
        }
        needsAttention = false
    }

    public func acknowledge() {
        needsAttention = false
    }

    public func tick() {
        let hadGap = refreshNow()
        if let focusOverride, focusOverride.focusMinutes != settings().focusMinutes {
            self.focusOverride = nil
            saveSnapshot()
        }
        if status == .idle {
            rollOverDayIfNeeded()
            return
        }
        guard !hadGap, status == .running, var session = active else { return }
        if let timeUpAt = session.timeUpAt {
            // Running over: the owner ends it, or 10 idle minutes do, at the
            // last input (never before zero). The sound already played at zero.
            let idle = idleSeconds()
            if idle >= Self.runOverIdleLimitSeconds {
                finish(session, outcome: .completed, at: max(timeUpAt, now.addingTimeInterval(-idle)), notify: false)
                needsAttention = true
                return
            }
        } else if let endsAt = session.endsAt, now >= endsAt {
            guard session.kind == .focus, settings().allowRunOver else {
                finish(session, outcome: .completed, at: endsAt)
                return
            }
            session.timeUpAt = endsAt
            active = session
            needsAttention = true
            saveSnapshot()
            onFinish?(session.kind)
            return
        }
        if lastSnapshotAt.map({ now.timeIntervalSince($0) >= Self.snapshotIntervalSeconds }) ?? true {
            saveSnapshot()
        }
    }

    /// Ends a focus that is running over as completed, with all its time.
    private func endRunOver() {
        guard let session = active, session.timeUpAt != nil else { return }
        finish(session, outcome: .completed, at: now, notify: false)
    }

    /// The Mac is about to sleep: sleep is blank time, so pause.
    public func systemWillSleep() {
        refreshNow()
        pause(asOf: now)
    }

    /// The app is quitting: log the session so far, as End early would.
    public func prepareForQuit() {
        refreshNow()
        endRunOver() // it reached zero: a finished focus, not an early end
        if status != .idle, let session = active {
            finish(session, outcome: .endedEarly, at: now)
        }
        saveSnapshot()
    }

    // MARK: - Internals

    /// Reads the clock. Every entry point calls this first, so if the engine
    /// hasn't heard from the app for longer than the blank-gap threshold while
    /// running (forced sleep, a stall, a late sleep notice), the session is
    /// paused as of the last moment it was seen: the gap is blank time.
    /// Returns whether that happened.
    @discardableResult
    private func refreshNow() -> Bool {
        let previous = lastSeen
        now = clock()
        lastSeen = now
        guard status == .running, now.timeIntervalSince(previous) > Self.blankGapSeconds else { return false }
        pause(asOf: previous)
        return true
    }

    private func pause(asOf moment: Date) {
        guard status == .running, var session = active else { return }
        let activeSeconds: TimeInterval
        if let timeUpAt = session.timeUpAt {
            // Past zero, the time over the planned length is the owner's to
            // keep, up to their last input: a Mac that sleeps from idleness
            // (before the 10-minute stop) mustn't count the minutes it sat idle.
            let lastInput = now.addingTimeInterval(-idleSeconds())
            activeSeconds = session.activeSeconds(at: max(timeUpAt, min(moment, lastInput)))
        } else {
            activeSeconds = min(TimeInterval(session.plannedSeconds), session.activeSeconds(at: moment))
        }
        session.accumulatedSeconds = activeSeconds
        session.lastResumedAt = nil
        active = session
        status = .paused
        saveSnapshot()
    }

    func saveSnapshot() {
        lastSnapshotAt = now
        snapshots.save(EngineSnapshot(
            active: active, savedAt: now, cyclePosition: cyclePosition,
            cycleDay: cycleDay, nextKind: nextKind, focusOverride: focusOverride))
    }

    /// Restores the cycle from the last run and logs a session the last run
    /// never got to finish (a crash or forced shutdown), up to its last checkpoint.
    private func recover(from snapshot: EngineSnapshot?) {
        guard let snapshot else { return }
        cyclePosition = snapshot.cyclePosition
        nextKind = snapshot.nextKind
        cycleDay = snapshot.cycleDay
        // Set against another Focus default (changed while the app was closed): gone.
        focusOverride = snapshot.focusOverride.flatMap { $0.focusMinutes == settings().focusMinutes ? $0 : nil }
        if let session = snapshot.active {
            if session.timeUpAt != nil {
                // It reached zero: a finished focus, with its time past zero up to the checkpoint.
                finish(session, outcome: .completed, at: snapshot.savedAt, notify: false)
            } else {
                let end = min(snapshot.savedAt, session.endsAt ?? snapshot.savedAt)
                finish(session, outcome: .endedEarly, at: end, notify: false)
            }
        }
        rollOverDayIfNeeded()
        saveSnapshot()
    }

    private func advanceCycle(after kind: SessionKind) {
        switch kind {
        case .focus:
            cyclePosition += 1
            nextKind = cyclePosition >= settings().sessionsBeforeLongBreak ? .longBreak : .shortBreak
        case .shortBreak:
            nextKind = .focus
        case .longBreak:
            nextKind = .focus
            cyclePosition = 0
        }
    }

    /// While idle on a later day than the cycle's last activity, start a fresh
    /// cycle — unless a session ended within the grace period, so a pending
    /// break earned just before midnight isn't swept away. A stale finish alert
    /// goes with the old cycle.
    private func rollOverDayIfNeeded() {
        let today = calendar.startOfDay(for: now)
        guard active == nil, today != cycleDay else { return }
        if let finished = lastFinishAt, now.timeIntervalSince(finished) < Self.dayRolloverGraceSeconds { return }
        cyclePosition = 0
        nextKind = .focus
        cycleDay = today
        needsAttention = false
    }

    /// Ends `session` at `end`, logging it unless it is a focus session ended
    /// before the one-minute minimum.
    private func finish(_ session: ActiveSession, outcome: Outcome, at end: Date, notify: Bool = true) {
        let measured = Int(session.activeSeconds(at: end).rounded())
        // A focus that ran over keeps all its time; otherwise at most the planned length.
        let activeSeconds = session.timeUpAt != nil ? measured : min(session.plannedSeconds, measured)
        active = nil
        status = .idle

        let tooShort = session.kind == .focus && outcome == .endedEarly
            && activeSeconds < Self.minimumLoggedFocusSeconds
        if tooShort {
            saveSnapshot()
            return
        }

        advanceCycle(after: session.kind)
        cycleDay = calendar.startOfDay(for: end)
        lastFinishAt = end
        sessions.save(SessionRecord(
            id: session.id, kind: session.kind, startedAt: session.startedAt, endedAt: end,
            plannedSeconds: session.plannedSeconds, activeSeconds: activeSeconds,
            outcome: outcome, origin: .manual))
        todayCache = nil
        savedSessionCount += 1
        saveSnapshot()

        if outcome == .completed, notify {
            needsAttention = true
            onFinish?(session.kind)
        }
    }
}
