import FocusNowCore
import SwiftUI

enum MainPage: Hashable { case timer, stats, settings }

/// Which page the main window shows, and which Settings section; the app sets
/// the page before showing the window. The section is kept while the app runs.
@MainActor @Observable
final class MainWindowState {
    var page: MainPage = .timer
    var settingsSection: SettingsSection = .cycle
}

/// The app window: Timer, Stats and Settings pages, switched from the toolbar
/// (or ⌘1 / ⌘2 / ⌘3). Switching isn't animated: it's frequent and often
/// keyboard-driven.
struct MainWindowView: View {
    @Bindable var state: MainWindowState
    let engine: TimerEngine
    let settings: SettingsStore
    let statsModel: StatsViewModel
    let calendarModel: CalendarModel
    let calendarPrefs: CalendarPreferences
    var onAction: (TimerControl) -> Void = { _ in }

    var body: some View {
        Group {
            switch state.page {
            case .timer:
                TimerPageView(
                    engine: engine, settings: settings, calendarModel: calendarModel, calendarPrefs: calendarPrefs,
                    onAction: onAction,
                    onShowCalendarSettings: {
                        state.settingsSection = .calendar
                        state.page = .settings
                    })
            case .stats: StatsView(model: statsModel)
            case .settings:
                SettingsView(settings: settings, state: state, calendarModel: calendarModel, calendarPrefs: calendarPrefs)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: $state.page) {
                    Text("Timer").tag(MainPage.timer)
                    Text("Stats").tag(MainPage.stats)
                    Text("Settings").tag(MainPage.settings)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
