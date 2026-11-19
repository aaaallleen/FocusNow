import FocusNowCore
import ServiceManagement
import SwiftUI

/// Settings apply as soon as they change; there is no Save button.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            Section("Timer") {
                minutesStepper("Focus", value: $settings.settings.focusMinutes)
                minutesStepper("Short break", value: $settings.settings.shortBreakMinutes)
                minutesStepper("Long break", value: $settings.settings.longBreakMinutes)
                Stepper(value: $settings.settings.sessionsBeforeLongBreak, in: TimerSettings.sessionsRange) {
                    row("Long break after", "\(settings.settings.sessionsBeforeLongBreak) "
                        + (settings.settings.sessionsBeforeLongBreak == 1 ? "session" : "sessions"))
                }
            }
            Section("Goal") {
                Stepper(value: $settings.settings.dailyGoalSeconds, in: TimerSettings.goalRange, step: 900) {
                    row("Daily focus goal", TimeFormat.duration(settings.settings.dailyGoalSeconds))
                }
            }
            Section("General") {
                Toggle("Play sound when a session ends", isOn: $settings.settings.soundOn)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginItemMessage {
                    Text(loginItemMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { refreshLoginItem() }
    }

    private func minutesStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: TimerSettings.minuteRange) {
            row(label, "\(value.wrappedValue) min")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
            refreshLoginItem()
        } catch {
            launchAtLogin = service.status == .enabled
            loginItemMessage = "Couldn't change the login item: \(error.localizedDescription)"
        }
    }

    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginItemMessage = status == .requiresApproval
            ? "Allow FocusNow in System Settings → General → Login Items."
            : nil
    }
}
