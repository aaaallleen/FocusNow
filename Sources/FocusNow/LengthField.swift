import SwiftUI

/// A number you can type or step: a text field, an optional unit, and a stepper.
///
/// Typed text commits on Return or when the field loses focus. Text that
/// `parse` can't read beeps and puts the previous value back; Escape, or
/// clearing the field, puts it back quietly. `parse` clamps, so out-of-range
/// numbers land on the nearest allowed value.
struct LengthField: View {
    /// What VoiceOver calls the field and its arrows, unit included, since the
    /// field reads only the number ("Focus, in minutes", "Daily focus goal").
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String?
    let parse: (String) -> Int?
    let format: (Int) -> String
    var fieldWidth: CGFloat = 52
    /// A fixed unit width lines up the steppers of rows with different units;
    /// the unit sits at its right, next to the stepper.
    var unitWidth: CGFloat?

    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var editID = UUID()
    /// Goes up each time typed text can't be read, to shake the field.
    @State private var rejections = 0
    @Environment(\.pendingEdits) private var pendingEdits

    init(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String?,
         parse: @escaping (String) -> Int?, format: @escaping (Int) -> String,
         fieldWidth: CGFloat = 52, unitWidth: CGFloat? = nil) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.parse = parse
        self.format = format
        self.fieldWidth = fieldWidth
        self.unitWidth = unitWidth
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: fieldWidth)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                .accessibilityLabel(label)
                .modifier(RejectShake(trigger: rejections))
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: unitWidth, alignment: .trailing)
                    .accessibilityHidden(true) // the field's value reads with its unit below
            }
            Stepper(label, value: stepperValue, in: range, step: step)
                .labelsHidden()
                .accessibilityValue(format(value) + (unit.map { " " + $0 } ?? ""))
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { old, new in
            // Follow changes made elsewhere (the stepper, another window) unless
            // the field holds typed text that hasn't been committed yet.
            if !focused || text == format(old) { text = format(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                pendingEdits?.register(editID) { commit() }
            } else {
                pendingEdits?.unregister(editID)
                commit()
            }
        }
        // Removed mid-edit (another section or page shown): focus never
        // reports leaving, so keep what was typed here.
        .onDisappear {
            pendingEdits?.unregister(editID)
            commit()
        }
    }

    /// The stepper steps from what was typed, not from the value it replaced.
    private var stepperValue: Binding<Int> {
        Binding(
            get: { value },
            set: { stepped in
                let delta = stepped - value
                if text != format(value), let parsed = parse(text) { value = parsed }
                value = min(max(value + delta, range.lowerBound), range.upperBound)
                text = format(value)
            })
    }

    private func commit() {
        if text != format(value), !InputFeedback.isBlank(text) {
            if let parsed = parse(text) {
                value = parsed
            } else {
                InputFeedback.rejected()
                rejections += 1
            }
        }
        text = format(value)
    }

    private func revert() {
        text = format(value)
        focused = false
    }
}
