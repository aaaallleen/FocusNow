import FocusNowCore
import SwiftUI

/// Page 1 of the main window: the timer, filling the page whether or not a
/// session is running. The cycle's lengths live in Settings → Cycle.
struct TimerPageView: View {
    let engine: TimerEngine
    let settings: SettingsStore
    var onAction: (TimerControl) -> Void = { _ in }

    @State private var pendingEdits = PendingEdits()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let diameter = min(min(size.width, size.height) * 0.7, size.height - 170)
            VStack(spacing: 22) {
                PhaseLabel(engine: engine, size: 13)
                TimerRing(engine: engine, diameter: max(diameter, 120), editable: true)
                TimerControlsRow(engine: engine, onAction: onAction)
                    .frame(maxWidth: 320)
                TodayBar(engine: engine, settings: settings)
                    .frame(maxWidth: 320)
            }
            // Phase changes crossfade (label, ring colour, controls), as in the popover.
            .animation(.easeInOut(duration: Theme.phaseFade), value: engine.phaseKey)
            .padding(.horizontal, 24)
            .frame(width: size.width, height: size.height)
        }
        .environment(\.pendingEdits, pendingEdits)
    }
}
