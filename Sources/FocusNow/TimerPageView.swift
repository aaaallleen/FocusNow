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
    @State private var pendingEdits = PendingEdits()

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
        .environment(\.pendingEdits, pendingEdits)
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
            TimerRing(engine: engine, diameter: diameter, editable: true)
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
            // One layout for every row: an aligned grid when it fits, all rows
            // stacked (label above field) when the window is narrow.
            ViewThatFits(in: .horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label).fixedSize()
                            row.field.fixedSize().gridColumnAlignment(.trailing)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.label)
                            row.field.fixedSize()
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private struct ConfigRow: Identifiable {
        let label: String
        let field: LengthField
        var id: String { label }
    }

    private var rows: [ConfigRow] {
        let after = settings.settings.sessionsBeforeLongBreak
        return [
            minutesRow("Focus", $settings.settings.focusMinutes),
            minutesRow("Short break", $settings.settings.shortBreakMinutes),
            minutesRow("Long break", $settings.settings.longBreakMinutes),
            ConfigRow(label: "Long break after", field: LengthField(
                "Long break after, in sessions", value: $settings.settings.sessionsBeforeLongBreak, range: TimerSettings.sessionsRange,
                step: 1, unit: after == 1 ? "session" : "sessions",
                parse: { LengthInput.sessions($0, in: TimerSettings.sessionsRange) },
                format: { "\($0)" }, fieldWidth: Self.fieldWidth, unitWidth: Self.unitWidth)),
        ]
    }

    private static let fieldWidth: CGFloat = 44
    private static let unitWidth: CGFloat = 54

    private func minutesRow(_ label: String, _ value: Binding<Int>) -> ConfigRow {
        ConfigRow(label: label, field: LengthField(
            "\(label), in minutes", value: value, range: TimerSettings.minuteRange, step: 1, unit: "min",
            parse: { LengthInput.minutes($0, in: TimerSettings.minuteRange) },
            format: { "\($0)" }, fieldWidth: Self.fieldWidth, unitWidth: Self.unitWidth))
    }
}
