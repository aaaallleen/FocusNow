import FocusNowCore
import ServiceManagement
import SwiftUI

/// The sections of the Settings page, in sidebar order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case cycle, goal, general, calendar, appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .cycle: "Cycle"
        case .goal: "Goal"
        case .general: "General"
        case .calendar: "Calendar"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .cycle: "arrow.triangle.2.circlepath"
        case .goal: "target"
        case .general: "gearshape"
        case .calendar: "calendar"
        case .appearance: "paintpalette"
        }
    }
}

/// Page 3 of the main window: a sidebar of sections beside the chosen one.
/// Settings apply as soon as they change; there is no Save button.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var state: MainWindowState
    let calendarModel: CalendarModel
    let calendarPrefs: CalendarPreferences
    let appearance: AppearancePreferences

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    private var colors: ThemeColors { ThemeColors(palette, scheme: scheme) }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.symbol).foregroundStyle(colors.focus)
                    }
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            Divider()
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A click on the sidebar's empty space would clear the selection; a section stays chosen.
    private var selection: Binding<SettingsSection?> {
        Binding(get: { state.settingsSection }, set: { if let section = $0 { state.settingsSection = section } })
    }

    @ViewBuilder private var pane: some View {
        switch state.settingsSection {
        case .cycle: CyclePane(settings: settings)
        case .goal: GoalPane(settings: settings)
        case .general: GeneralPane(settings: settings)
        case .calendar: CalendarPane(model: calendarModel, preferences: calendarPrefs)
        case .appearance: AppearancePane(preferences: appearance)
        }
    }
}

/// A label with its field. A grouped form lines a row up by text baseline, and
/// a field with a stepper reports one that sits the label too high; reporting
/// both sides' centres as their baselines centres them instead.
private struct SettingsRow<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    init(_ label: String, @ViewBuilder field: () -> Field) {
        self.label = label
        self.field = field()
    }

    var body: some View {
        LabeledContent {
            field.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        } label: {
            Text(label).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        }
    }
}

/// The lengths every session uses. Editable during a session too: a change
/// applies from the next one.
private struct CyclePane: View {
    @Bindable var settings: SettingsStore

    private static let fieldWidth: CGFloat = 44
    private static let unitWidth: CGFloat = 54

    var body: some View {
        let after = settings.settings.sessionsBeforeLongBreak
        Form {
            Section {
                minutesRow("Focus", $settings.settings.focusMinutes)
                minutesRow("Short break", $settings.settings.shortBreakMinutes)
                minutesRow("Long break", $settings.settings.longBreakMinutes)
                SettingsRow("Long break after") {
                    LengthField(
                        "Long break after, in sessions", value: $settings.settings.sessionsBeforeLongBreak,
                        range: TimerSettings.sessionsRange, step: 1, unit: after == 1 ? "session" : "sessions",
                        parse: { LengthInput.sessions($0, in: TimerSettings.sessionsRange) },
                        format: { "\($0)" }, fieldWidth: Self.fieldWidth, unitWidth: Self.unitWidth)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func minutesRow(_ label: String, _ value: Binding<Int>) -> some View {
        SettingsRow(label) {
            LengthField(
                "\(label), in minutes", value: value, range: TimerSettings.minuteRange, step: 1, unit: "min",
                parse: { LengthInput.minutes($0, in: TimerSettings.minuteRange) },
                format: { "\($0)" }, fieldWidth: Self.fieldWidth, unitWidth: Self.unitWidth)
        }
    }
}

private struct GoalPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsRow("Daily focus goal") {
                    LengthField(
                        "Daily focus goal", value: $settings.settings.dailyGoalSeconds, range: TimerSettings.goalRange,
                        step: 900, unit: nil, parse: LengthInput.goalSeconds,
                        format: TimeFormat.duration, fieldWidth: 72)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Play sound when a session ends", isOn: $settings.settings.soundOn)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginItemMessage {
                    Text(loginItemMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLoginItem() }
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
