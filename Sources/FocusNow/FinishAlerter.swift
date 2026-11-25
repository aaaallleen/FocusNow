import AppKit
import FocusNowCore
@preconcurrency import UserNotifications

/// What happens alongside the popover when a countdown reaches zero: the app's
/// own sound (so it plays even under Do Not Disturb or a Focus mode) and a
/// silent system notification.
@MainActor
final class FinishAlerter: NSObject, UNUserNotificationCenterDelegate {
    static let soundName = "Glass"

    private let settings: SettingsStore
    private var askedForPermission = false
    /// Off only in the self-check, so a test run makes no noise and asks for no permission.
    var isSelfCheck = false
    var onNotificationClicked: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asked the first time a session starts, not at launch. A denial is fine:
    /// the sound, the flash and the popover still happen.
    func requestAuthorizationIfNeeded() {
        guard !askedForPermission else { return }
        askedForPermission = true
        // The async form, not the completion handler: from this @MainActor
        // class, the handler is inferred main-actor-isolated, and
        // UserNotifications calls it on its own queue, which traps.
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) }
    }

    /// The notification's title and body. A focus running over hasn't ended:
    /// its time is up, and the clock keeps going.
    static func message(for kind: SessionKind, runningOver: Bool) -> (title: String, body: String) {
        if runningOver { return ("Focus time is up", "The clock keeps running until you start your break.") }
        if kind == .focus { return ("Focus session finished", "Start your break when you're ready.") }
        return ("Break finished", "Ready for the next focus session?")
    }

    /// Returns whether a sound was (or, in the self-check, would have been) played.
    @discardableResult
    func sessionFinished(_ kind: SessionKind, runningOver: Bool = false) -> Bool {
        var played = false
        if settings.settings.soundOn, let sound = NSSound(named: Self.soundName) {
            played = isSelfCheck ? true : sound.play()
        }
        guard !isSelfCheck else { return played }

        let content = UNMutableNotificationContent()
        (content.title, content.body) = Self.message(for: kind, runningOver: runningOver)
        content.sound = nil // the app's own sound is the only sound
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        return played
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.onNotificationClicked?() }
    }
}
