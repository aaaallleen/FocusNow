import AppKit
import FocusNowCore
import SwiftUI

/// Settings → Appearance: light or dark, the colourway, the owner's own four
/// colours when Custom is chosen, and a preview of both modes.
struct AppearancePane: View {
    @Bindable var preferences: AppearancePreferences

    private static let slots: [(PaletteSlot, String, String)] = [
        (.focusLight, "Focus, light mode",
         "The ring and the main button during focus, the goal bar, the Stats charts and calendar blocks, and the Settings sidebar icons, in light mode."),
        (.focusDark, "Focus, dark mode", "The same places as color 1, in dark mode."),
        (.breakLight, "Break, light mode",
         "The ring and the main button during a short or long break, and the menu bar timer during a break, in light mode."),
        (.breakDark, "Break, dark mode", "The same places as color 3, in dark mode."),
    ]

    private var isCustom: Bool { preferences.colorwayID == AppearancePreferences.customID }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $preferences.mode) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
            }
            Section("Colorway") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Colorway.presets) { way in
                        ColorwayTile(name: way.name, selected: preferences.colorwayID == way.id,
                                     action: { preferences.choosePreset(way.id) }) {
                            PresetSwatch(palette: way.palette)
                        }
                    }
                    ColorwayTile(name: "Custom", selected: isCustom, action: { preferences.chooseCustom() }) {
                        CustomSwatch()
                    }
                }
                .padding(.vertical, 2)
            }
            if isCustom {
                Section {
                    ForEach(Array(Self.slots.enumerated()), id: \.offset) { index, slot in
                        ColorWellRow(number: index + 1, title: slot.1, detail: slot.2, color: binding(for: slot.0))
                    }
                } header: {
                    Text("Your colors")
                } footer: {
                    Text("Custom starts from the colorway you had picked. Button text switches between black and white to stay readable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Preview") {
                HStack(spacing: 10) {
                    PreviewPanel(title: "Light").environment(\.colorScheme, .light)
                    PreviewPanel(title: "Dark").environment(\.colorScheme, .dark)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        // "Your colors" eases in and out. Only when Custom is picked or left:
        // one preset to another recolours at once, for comparing them.
        .animation(Theme.easeOut(0.25), value: isCustom)
    }

    /// A colour that can't be read as sRGB (a pattern) keeps the colour before it.
    private func binding(for slot: PaletteSlot) -> Binding<Color> {
        Binding(
            get: { Color(preferences.palette[slot]) },
            set: { color in
                guard let rgb = SRGBColor(NSColor(color)) else { return }
                preferences.setCustom(rgb, for: slot)
            })
    }
}

/// One colourway to choose: a swatch and its name, outlined when chosen.
private struct ColorwayTile<Swatch: View>: View {
    let name: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let swatch: Swatch

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                swatch.frame(width: 22, height: 22)
                Text(name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The tile as drawn, shrinking to 0.97 while pressed like every other control.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .animation(.easeOut(duration: Theme.pressDuration), value: configuration.isPressed)
    }
}

/// A circle split between the focus and break colours (light-mode shades).
private struct PresetSwatch: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            Color(palette.focusLight)
            Color(palette.breakLight)
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
    }
}

private struct CustomSwatch: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// A colour well, its number, and where the colour goes.
private struct ColorWellRow: View {
    let number: Int
    let title: String
    let detail: String
    let color: Binding<Color>

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ColorPicker(title, selection: color, supportsOpacity: false)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary))
                        .accessibilityHidden(true)
                    Text(title).font(.system(size: 13, weight: .medium))
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The chosen colours in one mode, drawn the way the app draws them. Colours
/// are explicit so the panel shows its own mode whatever the window's is.
private struct PreviewPanel: View {
    let title: String

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var colors: ThemeColors { ThemeColors(palette, dark: dark) }
    private var background: Color { dark ? Color(white: 0.12) : Color(white: 0.96) }
    private var primary: Color { dark ? Color(white: 0.95) : Color(white: 0.11) }
    private var secondary: Color { dark ? Color(white: 0.6) : Color(white: 0.53) }
    private var track: Color { dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1) }
    private var soft: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            menuBar
            ring(diameter: 64, progress: 0.68, color: colors.focus, label: "17:24")
            pill("Start focus", fill: colors.focus, text: colors.text(on: .focus))
            HStack(spacing: 4) {
                pill("−", fill: soft, text: primary)
                pill("+", fill: soft, text: primary)
            }
            Capsule().fill(track).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in Capsule().fill(colors.focus).frame(width: geo.size.width * 0.62) }
                }
            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach([0.4, 0.75, 0.55, 0.9, 0.3, 0.65, 0.8], id: \.self) { h in
                        RoundedRectangle(cornerRadius: 2).fill(colors.focus).frame(height: 30 * h)
                    }
                }
                .frame(height: 30, alignment: .bottom)
                VStack(spacing: 4) {
                    ring(diameter: 26, progress: 0.4, color: colors.rest, label: nil)
                    pill("Start break", fill: colors.rest, text: colors.text(on: .shortBreak)).fixedSize()
                }
            }
            HStack(spacing: 6) {
                Text("Now").fontWeight(.semibold).foregroundStyle(colors.focus)
                Text("Standup").foregroundStyle(primary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(background))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview, \(title.lowercased()) mode")
    }

    /// The menu bar during a break: the timer in the break colour.
    private var menuBar: some View {
        HStack(spacing: 4) {
            Spacer()
            Image(systemName: "cup.and.saucer.fill")
            Text("4:12").monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(colors.rest)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(dark ? Color(white: 0.2) : Color(white: 0.88)))
    }

    private func ring(diameter: CGFloat, progress: Double, color: Color, label: String?) -> some View {
        let width = diameter * 8 / 150 * 1.6
        return ZStack {
            Circle().inset(by: width / 2).stroke(track, lineWidth: width)
            Circle().inset(by: width / 2).trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label).font(.system(size: diameter * 0.22, weight: .light)).monospacedDigit().foregroundStyle(primary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func pill(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
    }
}
