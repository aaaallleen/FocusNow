import AppKit
import FocusNowCore
import SwiftUI

/// Settings → Calendar: calendar access, the Timer page switch, and which
/// calendars count.
struct CalendarPane: View {
    let model: CalendarModel
    @Bindable var preferences: CalendarPreferences

    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    var body: some View {
        Form {
            Section("Calendar access") {
                access
            }
            Section {
                Toggle("Show today's events on the Timer page", isOn: $preferences.showOnTimerPage)
            }
            if model.access.canRead {
                if model.groups.isEmpty {
                    Section {
                        Text("No calendars on this Mac. Add an account in the Calendar app.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.groups, id: \.account) { group in
                        Section(group.account) {
                            ForEach(group.calendars) { calendar in
                                calendarRow(calendar)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // When access is allowed (or taken away), the calendars ease in (or out).
        .animation(Theme.easeOut(0.3), value: model.access)
    }

    @ViewBuilder private var access: some View {
        switch model.access {
        case .notAsked:
            HStack {
                Text("FocusNow can show your calendar events on the Timer page.")
                Spacer()
                Button("Allow Access…") { Task { await model.requestAccess() } }
            }
        case .denied, .writeOnly:
            HStack {
                Text("Calendar access is off.")
                Spacer()
                Button("Open Privacy & Security") { NSWorkspace.shared.open(Self.privacyURL) }
            }
        case .granted:
            Text("Reading calendars on this Mac.")
        }
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        Toggle(isOn: Binding(
            get: { model.isShown(calendar.id) },
            set: { model.setShown($0, calendarID: calendar.id) }
        )) {
            HStack(spacing: 6) {
                Circle().fill(Color(calendar.color)).frame(width: 9, height: 9)
                Text(calendar.title)
            }
            // The gap between the dot and the name toggles too.
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(calendar.title)
    }
}

extension Color {
    /// A calendar's own colour, as the Calendar app shows it.
    init(_ color: CalendarColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
