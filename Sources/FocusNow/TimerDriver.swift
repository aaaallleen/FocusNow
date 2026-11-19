import AppKit
import FocusNowCore

/// Ticks the engine twice a second and tells it when the Mac goes to sleep.
///
/// While a session is running or waiting for attention it holds a process
/// activity, which keeps App Nap from delaying the ticks. A delay over the
/// engine's blank-gap threshold would otherwise pause the session by mistake.
/// Idle system sleep is still allowed.
@MainActor
final class TimerDriver {
    private let engine: TimerEngine
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    init(engine: TimerEngine) {
        self.engine = engine
    }

    func start() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.systemWillSleep() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        tick()
    }

    private func tick() {
        engine.tick()
        let needsTicks = engine.status == .running || engine.needsAttention
        if needsTicks, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Focus session countdown")
        } else if !needsTicks, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}
