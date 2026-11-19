import SwiftUI

/// A number you can type or step: a text field, an optional unit, and a stepper.
///
/// Typed text commits on Return or when the field loses focus. Text that
/// `parse` can't read puts the previous value back; Escape does the same.
/// `parse` clamps, so out-of-range numbers land on the nearest allowed value.
struct LengthField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String?
    let parse: (String) -> Int?
    let format: (Int) -> String
    var fieldWidth: CGFloat = 52

    @State private var text = ""
    @FocusState private var focused: Bool

    init(value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String?,
         parse: @escaping (String) -> Int?, format: @escaping (Int) -> String, fieldWidth: CGFloat = 52) {
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.parse = parse
        self.format = format
        self.fieldWidth = fieldWidth
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
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { old, new in
            // Follow changes made elsewhere (the stepper, another window) unless
            // the field holds typed text that hasn't been committed yet.
            if !focused || text == format(old) { text = format(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        if text != format(value), let parsed = parse(text) { value = parsed }
        text = format(value)
    }

    private func revert() {
        text = format(value)
        focused = false
    }
}
