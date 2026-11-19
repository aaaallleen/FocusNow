import FocusNowCore
import SwiftUI

enum MainPage: Hashable { case timer, stats }

/// Which page the main window shows; the app sets it before showing the window.
@MainActor @Observable
final class MainWindowState {
    var page: MainPage = .timer
}

/// The app window: Timer and Stats pages, switched from the toolbar (or ⌘1 / ⌘2).
/// Switching isn't animated: it's frequent and often keyboard-driven.
struct MainWindowView: View {
    @Bindable var state: MainWindowState
    let engine: TimerEngine
    let settings: SettingsStore
    let statsModel: StatsViewModel
    var onAction: (TimerControl) -> Void = { _ in }

    var body: some View {
        Group {
            switch state.page {
            case .timer: TimerPageView(engine: engine, settings: settings, onAction: onAction)
            case .stats: StatsView(model: statsModel)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: $state.page) {
                    Text("Timer").tag(MainPage.timer)
                    Text("Stats").tag(MainPage.stats)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
