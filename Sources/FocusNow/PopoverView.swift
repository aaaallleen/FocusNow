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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: SessionKind { engine.active?.kind ?? engine.nextKind }
    private var tint: Color { Theme.color(for: kind) }
    /// Changes only when the phase or control set changes, never per second.
    private var phaseKey: String { "\(engine.status)-\(kind)-\(engine.needsAttention)" }

    var body: some View {
        VStack(spacing: 14) {
            Text(engine.phaseLabel)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            ring
            controls
            today
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 230)
        .animation(.easeInOut(duration: Theme.phaseFade), value: phaseKey)
    }

    // MARK: Ring

    /// A finished countdown stays full until the owner starts the next phase.
    private var ringProgress: Double {
        engine.status == .idle && engine.needsAttention ? 1 : engine.progress
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Sweeps linearly between ticks so it reads as continuous motion.
                .animation(engine.status == .running ? .linear(duration: 0.5) : nil, value: ringProgress)
            Text(TimeFormat.clock(engine.remainingSeconds))
                .font(.system(size: 34, weight: .light))
                .monospacedDigit()
                .contentTransition(.identity)
        }
        .frame(width: 150, height: 150)
        // A new session gets a fresh ring, so it never sweeps backwards.
        .id(engine.active?.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: Controls

    private var controls: some View {
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

    // MARK: Today

    private var today: some View {
        let done = engine.todayFocusSeconds()
        let goal = settings.settings.dailyGoalSeconds
        return VStack(spacing: 5) {
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

    // MARK: Footer

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
