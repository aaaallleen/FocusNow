import FocusNowCore
import SwiftUI

// The pieces of the timer shared by the popover and the Timer page.

extension TimerEngine {
    /// The session kind on screen: the running one, or else the next one.
    var displayedKind: SessionKind { active?.kind ?? nextKind }

    /// Changes only when the phase or control set changes, never per second.
    var phaseKey: String { "\(status)-\(displayedKind)-\(needsAttention)" }
}

/// "FOCUS · 1 of 4", "BREAK", "LONG BREAK".
struct PhaseLabel: View {
    let engine: TimerEngine
    var size: CGFloat = 11

    var body: some View {
        Text(engine.phaseLabel)
            .font(.system(size: size, weight: .semibold))
            .tracking(0.8 * size / 11)
            .foregroundStyle(.secondary)
    }
}

/// The countdown ring with the digits inside. Every measurement scales with
/// `diameter`; the popover uses 150.
struct TimerRing: View {
    let engine: TimerEngine
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { diameter * 8 / 150 }
    private var tint: Color { Theme.color(for: engine.displayedKind) }

    /// A finished countdown stays full until the owner starts the next phase.
    private var progress: Double {
        engine.status == .idle && engine.needsAttention ? 1 : engine.progress
    }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Sweeps linearly between ticks so it reads as continuous motion.
                .animation(engine.status == .running ? .linear(duration: 0.5) : nil, value: progress)
            Text(TimeFormat.clock(engine.remainingSeconds))
                .font(.system(size: diameter * 34 / 150, weight: .light))
                .monospacedDigit()
                .contentTransition(.identity)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, lineWidth * 1.5)
        }
        .frame(width: diameter, height: diameter)
        // A new session gets a fresh ring, so it never sweeps backwards.
        .id(engine.active?.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// The buttons for the engine's current state: −/+ and Start, Pause and End early, and so on.
struct TimerControlsRow: View {
    let engine: TimerEngine
    var onAction: (TimerControl) -> Void = { _ in }

    private var tint: Color { Theme.color(for: engine.displayedKind) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(engine.controls, id: \.self) { control in
                if control == .adjustLength {
                    adjustButtons
                } else {
                    Button(title(for: control)) { perform(control) }
                        .buttonStyle(PressableButtonStyle(prominent: isPrimary(control), tint: tint))
                }
            }
        }
    }

    private var adjustButtons: some View {
        HStack(spacing: 4) {
            Button { engine.adjustNextFocus(byMinutes: -TimerEngine.adjustStepMinutes) } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Five minutes shorter")
            Button { engine.adjustNextFocus(byMinutes: TimerEngine.adjustStepMinutes) } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Five minutes longer")
        }
        .buttonStyle(PressableButtonStyle(compact: true))
        .fixedSize()
    }

    private func perform(_ control: TimerControl) {
        switch control {
        case .startFocus, .startBreak: engine.start()
        case .skipBreak, .skip: engine.skipBreak()
        case .pause: engine.pause()
        case .resume: engine.resume()
        case .endEarly: engine.endEarly()
        case .cancel: engine.cancel()
        case .adjustLength: break
        }
        onAction(control)
    }

    private func title(for control: TimerControl) -> String {
        switch control {
        case .startFocus: "Start focus"
        case .startBreak: "Start break"
        case .skipBreak: "Skip break"
        case .pause: "Pause"
        case .resume: "Resume"
        case .endEarly: "End early"
        case .cancel: "Cancel"
        case .skip: "Skip"
        case .adjustLength: ""
        }
    }

    private func isPrimary(_ control: TimerControl) -> Bool {
        [.startFocus, .startBreak, .pause, .resume].contains(control)
    }
}

/// "Today 1h 20m … Goal 4h" over a progress bar.
struct TodayBar: View {
    let engine: TimerEngine
    let settings: SettingsStore

    var body: some View {
        let done = engine.todayFocusSeconds()
        let goal = settings.settings.dailyGoalSeconds
        VStack(spacing: 5) {
            HStack {
                Text("Today \(TimeFormat.duration(done))")
                Spacer()
                Text("Goal \(TimeFormat.duration(goal))")
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            GoalBar(fraction: goal > 0 ? min(1, Double(done) / Double(goal)) : 0)
                .frame(height: 6)
        }
    }
}

struct GoalBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.focus).frame(width: geo.size.width * fraction)
            }
        }
    }
}

/// Every pressable control: scales to 0.97 on press over 0.15 s, ease-out.
struct PressableButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = Theme.focus
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize() // labels never truncate; spare width is shared out instead
            .padding(.vertical, 6)
            .padding(.horizontal, compact ? 8 : 6)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.08))))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .animation(.easeOut(duration: Theme.pressDuration), value: configuration.isPressed)
    }
}

/// Small text buttons in the popover footer.
struct FooterButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11))
            .foregroundStyle(hovering ? .primary : .secondary)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .animation(.easeOut(duration: Theme.pressDuration), value: configuration.isPressed)
    }
}
