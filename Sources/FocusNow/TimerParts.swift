import FocusNowCore
import SwiftUI

// The pieces of the timer shared by the popover and the Timer page.

extension TimerEngine {
    /// The session kind on screen: the running one, or else the next one.
    var displayedKind: SessionKind { active?.kind ?? nextKind }

    /// Changes only when the phase or control set changes, never per second.
    var phaseKey: String { "\(status)-\(displayedKind)-\(needsAttention)" }
}

/// The fields on one surface (the Timer page, or the popover) that hold typed
/// text not yet applied. A control on that surface applies them before it acts,
/// so typing a length and then clicking Start (or −/+) uses what was typed.
@MainActor
final class PendingEdits {
    private var commits: [UUID: () -> Void] = [:]

    func register(_ id: UUID, commit: @escaping () -> Void) { commits[id] = commit }
    func unregister(_ id: UUID) { commits[id] = nil }

    func commitAll() {
        for commit in Array(commits.values) { commit() }
    }
}

extension EnvironmentValues {
    @Entry var pendingEdits: PendingEdits? = nil
}

/// Typed text that couldn't be read gets the standard macOS beep, so a value
/// that quietly snapped back isn't mistaken for one that was applied.
@MainActor
enum InputFeedback {
    /// How many times typed text was rejected (the self-check reads it).
    private(set) static var rejections = 0

    static func rejected() {
        rejections += 1
        if DebugSnapshots.directory == nil { NSSound.beep() }
    }

    /// Cleared text isn't a mistake to beep at; the field just keeps its value.
    nonisolated static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Shows `cursor` over the area it backs. AppKit's cursor rects put the arrow
/// back by themselves when the pointer leaves or the window closes, so the
/// cursor can't stay stuck the way a pushed one can.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorView { CursorView(cursor: cursor) }
    func updateNSView(_ view: CursorView, context: Context) {}

    final class CursorView: NSView {
        let cursor: NSCursor

        init(cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil } // clicks belong to the control
    }
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
///
/// When `editable`, the digits can be clicked before a focus session to type
/// the next session's length (whole minutes). Return or clicking away applies
/// it; Escape, unreadable text, or the session starting elsewhere drops it.
struct TimerRing: View {
    let engine: TimerEngine
    let diameter: CGFloat
    var editable = false
    var onBeginEditing: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var draft = ""
    @State private var initialDraft = ""
    @FocusState private var fieldFocused: Bool
    @State private var editID = UUID()
    /// Goes up each time typed text can't be read, to shake the digits.
    @State private var rejections = 0
    @Environment(\.pendingEdits) private var pendingEdits

    private var lineWidth: CGFloat { diameter * 8 / 150 }
    private var tint: Color { ThemeColors(palette, scheme: scheme).color(for: engine.displayedKind) }
    private var digitFont: Font { .system(size: diameter * 34 / 150, weight: .light) }
    private var canEdit: Bool { editable && engine.controls.contains(.adjustLength) }

    /// A finished countdown stays full until the owner starts the next phase.
    private var progress: Double {
        engine.status == .idle && engine.needsAttention ? 1 : engine.progress
    }

    var body: some View {
        // The stroke is drawn inside the frame, so the frame is the ring you see.
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Sweeps linearly between ticks so it reads as continuous motion.
                .animation(engine.status == .running ? .linear(duration: 0.5) : nil, value: progress)
            digits
                .padding(.horizontal, lineWidth * 1.5)
                .modifier(RejectShake(trigger: rejections, distance: diameter * 6 / 150))
        }
        .frame(width: diameter, height: diameter)
        // A new session gets a fresh ring, so it never sweeps backwards.
        .id(engine.active?.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .onChange(of: canEdit) { _, can in
            if !can { finishEditing(apply: false) } // a session started elsewhere
        }
    }

    private var clockText: some View {
        Text(engine.clockLabel) // "+4:12" past zero while running over
            .font(digitFont)
            .monospacedDigit()
            .contentTransition(.identity)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder private var digits: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(digitFont)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: diameter * 0.6)
                .focused($fieldFocused)
                .onSubmit { finishEditing(apply: true) }
                .onExitCommand { finishEditing(apply: false) }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { finishEditing(apply: true) } // clicked away
                }
                .onAppear { DispatchQueue.main.async { fieldFocused = true } }
                // Removed mid-edit (another page shown): focus never reports
                // leaving, so apply what was typed here. A session started
                // elsewhere still drops it: the length then can't be set.
                .onDisappear { finishEditing(apply: true) }
                .accessibilityLabel("Next session's length in minutes")
        } else if canEdit {
            // VoiceOver reads the time, as it does when the digits aren't
            // clickable, then the help as the hint.
            Button(action: beginEditing) { clockText }
                .buttonStyle(.plain)
                .background(CursorArea(cursor: .iBeam).allowsHitTesting(false))
                .help("Click to type the next session's length")
                .accessibilityIdentifier(Self.digitsIdentifier)
        } else {
            clockText
                .accessibilityIdentifier(Self.digitsIdentifier) // the self-check measures them
        }
    }

    private func beginEditing() {
        draft = "\(engine.plannedSecondsForNext / 60)"
        initialDraft = draft
        editing = true
        pendingEdits?.register(editID) { finishEditing(apply: true) }
        onBeginEditing()
    }

    private func finishEditing(apply: Bool) {
        guard editing else { return }
        editing = false
        pendingEdits?.unregister(editID)
        // Cleared means never mind: the length stays, quietly.
        guard apply, draft != initialDraft, !InputFeedback.isBlank(draft) else { return }
        guard let minutes = LengthInput.timerDigits(draft, in: TimerSettings.minuteRange) else {
            InputFeedback.rejected()
            // After the field has turned back into the digits: a shake asked for
            // in the same update as that swap doesn't play.
            Task { rejections += 1 }
            return
        }
        engine.setNextFocus(minutes: minutes)
    }

    /// Finds the digits (the self-check presses and measures them by this).
    static let digitsIdentifier = "next-session-length"
}

/// The buttons for the engine's current state, in two rows: the main action
/// (Start, Pause or Resume) alone on top, the others sharing the row beneath.
/// Every state has both rows, so nothing below moves when a session starts.
struct TimerControlsRow: View {
    let engine: TimerEngine
    var onAction: (TimerControl) -> Void = { _ in }

    @Environment(\.pendingEdits) private var pendingEdits
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.timerScale) private var scale

    private var colors: ThemeColors { ThemeColors(palette, scheme: scheme) }

    var body: some View {
        let rows = engine.controlRows
        VStack(spacing: 6 * scale) {
            button(rows.main)
            HStack(spacing: 6 * scale) {
                ForEach(rows.others, id: \.self) { control in
                    if control == .adjustLength {
                        adjustButtons
                    } else {
                        button(control)
                    }
                }
            }
        }
    }

    private func button(_ control: TimerControl) -> some View {
        Button(Self.title(for: control)) { perform(control) }
            .buttonStyle(PressableButtonStyle(
                // Only the top button is filled. Running over puts Pause (or,
                // paused, Start break) in the row beneath, where it stays plain.
                prominent: control == engine.controlRows.main, tint: colors.color(for: engine.displayedKind),
                text: colors.text(on: engine.displayedKind), scale: scale))
    }

    private var adjustButtons: some View {
        HStack(spacing: 6 * scale) {
            // The glyphs get a text line's height, or the − button (a 2 pt
            // glyph) would be shorter than the + button and the main button.
            Button { adjust(by: -TimerEngine.adjustStepMinutes) } label: {
                Image(systemName: "minus").frame(height: 15 * scale)
            }
            .accessibilityLabel("Five minutes shorter")
            Button { adjust(by: TimerEngine.adjustStepMinutes) } label: {
                Image(systemName: "plus").frame(height: 15 * scale)
            }
            .accessibilityLabel("Five minutes longer")
        }
        .buttonStyle(PressableButtonStyle(scale: scale))
    }

    /// Counts as answering a finish, as Start does.
    private func adjust(by minutes: Int) {
        pendingEdits?.commitAll()
        engine.adjustNextFocus(byMinutes: minutes)
        onAction(.adjustLength)
    }

    private func perform(_ control: TimerControl) {
        pendingEdits?.commitAll()
        switch control {
        case .startFocus, .startBreak, .startFlow: engine.start()
        case .skipBreak, .skip: engine.skipBreak()
        case .pause: engine.pause()
        case .resume: engine.resume()
        case .endEarly: engine.endEarly()
        case .cancel: engine.cancel()
        case .stop: engine.stop()
        case .adjustLength: break
        }
        onAction(control)
    }

    static func title(for control: TimerControl) -> String {
        switch control {
        case .startFocus: "Start focus"
        case .startBreak: "Start break"
        case .startFlow: "Start flow"
        case .stop: "Stop"
        case .skipBreak: "Skip break"
        case .pause: "Pause"
        case .resume: "Resume"
        case .endEarly: "End early"
        case .cancel: "Cancel"
        case .skip: "Skip"
        case .adjustLength: ""
        }
    }
}

/// "Today 1h 20m … Goal 4h" over a progress bar.
struct TodayBar: View {
    let engine: TimerEngine
    let settings: SettingsStore

    @Environment(\.timerScale) private var scale

    var body: some View {
        let done = engine.todayFocusSeconds()
        let goal = settings.settings.dailyGoalSeconds
        VStack(spacing: 5 * scale) {
            HStack {
                Text("Today \(TimeFormat.duration(done))")
                Spacer()
                Text("Goal \(TimeFormat.duration(goal))")
            }
            .font(.system(size: 11 * scale))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            GoalBar(fraction: goal > 0 ? min(1, Double(done) / Double(goal)) : 0)
                .frame(height: 6 * scale)
        }
    }
}

struct GoalBar: View {
    let fraction: Double

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(ThemeColors(palette, scheme: scheme).focus).frame(width: geo.size.width * fraction)
            }
        }
    }
}

/// Every pressable control: scales to 0.97 on press over 0.15 s, ease-out.
struct PressableButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = Color(Colorway.standard.palette.focusLight)
    /// The label colour on a prominent fill.
    var text: Color = .white
    var compact = false
    /// The Timer page's zoom; 1 everywhere else.
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12 * scale, weight: .medium))
            .lineLimit(1)
            .fixedSize() // labels never truncate; spare width is shared out instead
            .padding(.vertical, 6 * scale)
            .padding(.horizontal, (compact ? 8 : 6) * scale)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(prominent ? AnyShapeStyle(text) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
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
