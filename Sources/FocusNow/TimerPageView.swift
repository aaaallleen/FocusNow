import FocusNowCore
import SwiftUI

/// Page 1 of the main window. With no session running, the timer sits beside
/// the cycle's configuration; once a session starts the configuration leaves
/// and the timer fills the window. It comes back when the session ends.
struct TimerPageView: View {
    let engine: TimerEngine
    @Bindable var settings: SettingsStore
    var onAction: (TimerControl) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The timer's share of the width while the configuration shows.
    static let timerShare: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            layout(in: geo.size, inSession: engine.isInSession)
                // Reduce Motion: crossfade between the two layouts instead of moving.
                .id(reduceMotion ? AnyHashable(engine.isInSession) : AnyHashable(0))
                .transition(.opacity)
        }
        .animation(reduceMotion ? .easeInOut(duration: Theme.phaseFade) : Theme.layoutShift,
                   value: engine.isInSession)
    }

    private func layout(in size: CGSize, inSession: Bool) -> some View {
        let timerWidth = inSession ? size.width : (size.width * Self.timerShare).rounded()
        let diameter = inSession
            ? min(min(size.width, size.height) * 0.7, size.height - 170)
            : min(timerWidth * 0.6, size.height - 190)
        return HStack(spacing: 0) {
            timerColumn(diameter: max(diameter, 120), inSession: inSession)
                .frame(width: timerWidth)
            if !inSession {
                Divider()
                configuration
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 12)))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Timer

    private func timerColumn(diameter: CGFloat, inSession: Bool) -> some View {
        VStack(spacing: inSession ? 22 : 16) {
            PhaseLabel(engine: engine, size: inSession ? 13 : 12)
            TimerRing(engine: engine, diameter: diameter)
            TimerControlsRow(engine: engine, onAction: onAction)
                .frame(maxWidth: 320)
                .animation(.easeInOut(duration: Theme.phaseFade), value: engine.phaseKey)
            TodayBar(engine: engine, settings: settings)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Configuration

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CYCLE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            minutesRow("Focus", $settings.settings.focusMinutes)
            minutesRow("Short break", $settings.settings.shortBreakMinutes)
            minutesRow("Long break", $settings.settings.longBreakMinutes)
            let after = settings.settings.sessionsBeforeLongBreak
            row("Long break after", LengthField(
                value: $settings.settings.sessionsBeforeLongBreak, range: TimerSettings.sessionsRange,
                step: 1, unit: after == 1 ? "session" : "sessions",
                parse: { LengthInput.sessions($0, in: TimerSettings.sessionsRange) },
                format: { "\($0)" }))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func minutesRow(_ label: String, _ value: Binding<Int>) -> some View {
        row(label, LengthField(
            value: value, range: TimerSettings.minuteRange, step: 1, unit: "min",
            parse: { LengthInput.minutes($0, in: TimerSettings.minuteRange) },
            format: { "\($0)" }))
    }

    /// Label and field on one line when there's room, stacked when the window is narrow.
    private func row(_ label: String, _ field: LengthField) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).fixedSize()
                Spacer(minLength: 12)
                field.fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                field.fixedSize()
            }
        }
    }
}
