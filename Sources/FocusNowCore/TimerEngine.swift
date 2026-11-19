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

    @ObservationIgnored private let settings: () -> TimerSettings
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
    /// A one-off length for the next focus session; cleared when it starts.
    public var nextFocusSecondsOverride: Int?
    /// Increments every time a session record is saved.
    public private(set) var savedSessionCount = 0

    @ObservationIgnored private var todayCache: (day: Date, seconds: Int)?
    /// The local day of the cycle's most recent activity; a new day starts a new cycle.
    @ObservationIgnored private var cycleDay: Date
    /// When the engine last heard from the app (a tick or an action).
    @ObservationIgnored private var lastSeen: Date
    @ObservationIgnored private var lastSnapshotAt: Date?

    public init(
        settings: @escaping () -> TimerSettings, sessions: SessionStore,
        snapshots: SnapshotStore, clock: @escaping () -> Date, calendar: Calendar
    ) {
        self.settings = settings
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

    public func start() {
        refreshNow()
        guard status == .idle else { return }
        rollOverDayIfNeeded()
        cycleDay = calendar.startOfDay(for: now)
        let planned = plannedSecondsForNext
        if nextKind == .focus { nextFocusSecondsOverride = nil }
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
    /// pending break before it starts. Does nothing when focus is current or next.
    public func skipBreak() {
        refreshNow()
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
        let previous = lastSeen
        refreshNow()
        if status == .idle {
            rollOverDayIfNeeded()
            return
        }
        guard status == .running, let session = active else { return }
        if now.timeIntervalSince(previous) > Self.blankGapSeconds {
            // The app wasn't running for a while (forced sleep, a stall): that gap is blank.
            pause(asOf: previous)
            return
        }
        if let endsAt = session.endsAt, now >= endsAt {
            finish(session, outcome: .completed, at: endsAt)
        } else if lastSnapshotAt.map({ now.timeIntervalSince($0) >= Self.snapshotIntervalSeconds }) ?? true {
            saveSnapshot()
        }
    }

    /// The Mac is about to sleep: sleep is blank time, so pause.
    public func systemWillSleep() {
        refreshNow()
        pause(asOf: now)
    }

    /// The app is quitting: log the session so far, as End early would.
    public func prepareForQuit() {
        refreshNow()
        if status != .idle, let session = active {
            finish(session, outcome: .endedEarly, at: now)
        }
        saveSnapshot()
    }

    // MARK: - Internals

    private func refreshNow() {
        now = clock()
        lastSeen = now
    }

    private func pause(asOf moment: Date) {
        guard status == .running, var session = active else { return }
        session.accumulatedSeconds = min(TimeInterval(session.plannedSeconds), session.activeSeconds(at: moment))
        session.lastResumedAt = nil
        active = session
        status = .paused
        saveSnapshot()
    }

    private func saveSnapshot() {
        lastSnapshotAt = now
        snapshots.save(EngineSnapshot(
            active: active, savedAt: now, cyclePosition: cyclePosition,
            cycleDay: cycleDay, nextKind: nextKind))
    }

    /// Restores the cycle from the last run and logs a session the last run
    /// never got to finish (a crash or forced shutdown), up to its last checkpoint.
    private func recover(from snapshot: EngineSnapshot?) {
        guard let snapshot else { return }
        cyclePosition = snapshot.cyclePosition
        nextKind = snapshot.nextKind
        cycleDay = snapshot.cycleDay
        if let session = snapshot.active {
            let end = min(snapshot.savedAt, session.endsAt ?? snapshot.savedAt)
            finish(session, outcome: .endedEarly, at: end, notify: false)
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

    /// While idle on a later day than the cycle's last activity, start a fresh cycle.
    private func rollOverDayIfNeeded() {
        let today = calendar.startOfDay(for: now)
        guard active == nil, today != cycleDay else { return }
        cyclePosition = 0
        nextKind = .focus
        cycleDay = today
    }

    /// Ends `session` at `end`, logging it unless it is a focus session ended
    /// before the one-minute minimum.
    private func finish(_ session: ActiveSession, outcome: Outcome, at end: Date, notify: Bool = true) {
        let activeSeconds = min(session.plannedSeconds, Int(session.activeSeconds(at: end).rounded()))
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
