import FocusNowCore
import SwiftUI

/// The popover under the menu bar item (layout A, "Ring").
struct PopoverView: View {
    let engine: TimerEngine
    let settings: SettingsStore
    var onAction: (TimerControl) -> Void = { _ in }
    var onStats: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            PhaseLabel(engine: engine)
            TimerRing(engine: engine, diameter: 150)
            TimerControlsRow(engine: engine, onAction: onAction)
            TodayBar(engine: engine, settings: settings)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 230)
        .animation(.easeInOut(duration: Theme.phaseFade), value: engine.phaseKey)
    }

    private var footer: some View {
        HStack {
            Button("Stats", systemImage: "chart.bar.xaxis", action: onStats)
            Spacer()
            Button("Settings", systemImage: "gearshape", action: onSettings)
            Spacer()
            Button("Quit", systemImage: "power", action: onQuit)
                .keyboardShortcut("q")
        }
        .buttonStyle(FooterButtonStyle())
    }
}
