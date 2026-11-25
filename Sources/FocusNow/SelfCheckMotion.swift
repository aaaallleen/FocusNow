import AppKit
import FocusNowCore
import SwiftUI

/// The self-check's motion phase, measured from the window's pixels sampled
/// about every frame while each motion plays:
/// - typed text that can't be read shakes (the Timer page digits and a Settings
///   field), and with Reduce Motion dims for a moment instead;
/// - a Colorway tile shrinks while it's held down, like every other button;
/// - the "Your colors" rows and the calendar list ease in, while switching from
///   one preset to another stays instant.
extension AppDelegate {
    func checkMotion(_ snap: DebugSnapshots) async {
        snap.note("== motion ==")
        snap.note("system reduce motion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) " +
            "(want false: the shake checks need it off)")
        engine.cancel()
        engine.skipBreak()
        closeAllWindows()
        await snap.wait(0.4)
        await checkDigitsShake(snap)
        await checkFieldShake(snap)
        await checkReducedShake(snap)
        await checkColorwayMotion(snap)
        await checkCalendarListMotion(snap)
        closeAllWindows()
        await snap.wait(0.4)
    }

    /// Text the digits can't read: they shake, then settle where they were.
    private func checkDigitsShake(_ snap: DebugSnapshots) async {
        showTimer()
        await snap.wait(0.6)
        guard let window = windows.mainWindow else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.4)
        guard let digits = snap.accessibilityFrame(of: TimerRing.digitsIdentifier, in: window) else {
            snap.note("no digits")
            return
        }
        // Inside the ring: the digits, and room either side for them to move into.
        let area = digits.insetBy(dx: -16, dy: digits.height * 0.2)
        let rest = snap.drawing(in: area, of: window)?.extent?.lowerBound
        let rejected = InputFeedback.rejections
        guard await snap.press(accessibilityLabel: TimerRing.digitsIdentifier, in: window),
              window.firstResponder is NSText else {
            snap.note("digits did not become a field")
            return
        }
        await snap.typeIntoFocusedField("abc", in: window)
        snap.sendKey("\r", keyCode: 36, to: window)
        let edges = await snap.sample(for: 0.6) { snap.drawing(in: area, of: window)?.extent?.lowerBound }
        snap.note("digits abc: \(Self.shake(edges, rest: rest)) beeped=\(InputFeedback.rejections - rejected) " +
            "(want moved ≥4 over ≥3 frames, settled ≤0.5, beeped 1)")
    }

    /// Text a Settings field can't read: the field shakes, then settles.
    private func checkFieldShake(_ snap: DebugSnapshots) async {
        mainState.settingsSection = .cycle
        showSettings()
        await snap.wait(0.6)
        guard let window = windows.mainWindow else {
            snap.note("no main window")
            return
        }
        let before = settings.settings.focusMinutes
        await snap.type("abc", intoField: 0, of: window)
        guard let field = snap.textFields(in: window).first else {
            snap.note("no Focus field")
            return
        }
        // The field and room to its left; the unit beside it stays put.
        let frame = window.convertToScreen(field.convert(field.bounds, to: nil))
        let area = NSRect(x: frame.minX - 16, y: frame.minY + 2, width: frame.width / 2 + 16, height: frame.height - 4)
        let rest = snap.drawing(in: area, of: window)?.extent?.lowerBound
        let rejected = InputFeedback.rejections
        snap.sendKey("\r", keyCode: 36, to: window)
        let edges = await snap.sample(for: 0.6) { snap.drawing(in: area, of: window)?.extent?.lowerBound }
        snap.note("focus field abc: \(Self.shake(edges, rest: rest)) beeped=\(InputFeedback.rejections - rejected) " +
            "focus=\(settings.settings.focusMinutes) (want moved ≥4 over ≥3 frames, settled ≤0.5, beeped 1, focus \(before))")
        window.makeFirstResponder(nil)
    }

    /// With Reduce Motion the shake becomes a moment of dimming, in place.
    private func checkReducedShake(_ snap: DebugSnapshots) async {
        let probe = ShakeProbe()
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 320, height: 160),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ShakeProbeView(probe: probe))
        window.orderFront(nil)
        await snap.wait(0.5)
        guard let text = snap.accessibilityFrame(of: ShakeProbeView.identifier, in: window) else {
            snap.note("no shake probe")
            window.close()
            return
        }
        let area = text.insetBy(dx: -16, dy: text.height * 0.2)
        let rest = snap.drawing(in: area, of: window)
        probe.count += 1
        let seen = await snap.sample(for: 0.6) { snap.drawing(in: area, of: window) }
        let ink = seen.compactMap { $0?.ink }
        let faintest = Double(ink.min() ?? 0) / Double(max(rest?.ink ?? 1, 1))
        let settled = Double(ink.last ?? 0) / Double(max(rest?.ink ?? 1, 1))
        snap.note("reduced motion: \(Self.shake(seen.map { $0?.extent?.lowerBound }, rest: rest?.extent?.lowerBound)) " +
            String(format: "faintest=%.2f settled=%.2f", faintest, settled) +
            " (want moved ≤0.5, faintest ≤0.6, settled ≥0.95)")
        window.close()
    }

    /// A tile shrinks while held; picking Custom eases its rows in and out;
    /// one preset to another recolours at once.
    private func checkColorwayMotion(_ snap: DebugSnapshots) async {
        appearancePrefs.choosePreset(Colorway.standard.id)
        mainState.settingsSection = .appearance
        showSettings()
        guard let window = windows.mainWindow else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 900))
        await snap.wait(0.8)
        let names = Colorway.presets.map(\.name) + ["Custom"]
        let tiles = names.compactMap { snap.accessibilityFrame(of: $0, in: window) }
        guard tiles.count == names.count, let teal = tiles.first, let content = window.contentView else {
            snap.note("colorway tiles: found \(tiles.count) of \(names.count)")
            return
        }

        // Held down, the chosen tile (its outline is easy to measure) shrinks.
        let tileArea = teal.insetBy(dx: -3, dy: -3)
        func width() -> CGFloat? { snap.drawing(in: tileArea, of: window)?.extent.map { $0.upperBound - $0.lowerBound } }
        let restWidth = width() ?? 0
        let centre = window.convertPoint(fromScreen: NSPoint(x: teal.midX, y: teal.midY))
        snap.mouse(.leftMouseDown, at: centre, in: window)
        let held = await snap.sample(for: 0.3) { width() }.compactMap { $0 }
        snap.mouse(.leftMouseUp, at: centre, in: window)
        let released = await snap.sample(for: 0.3) { width() }.compactMap { $0 }
        // A scaled outline lands between pixels; its soft edges add up to a point.
        let heldWidth = held.last ?? 0
        let between = held.filter { $0 < restWidth - 0.5 && $0 > heldWidth + 0.5 }.count
        snap.note(String(format: "tile held: rest=%.1f held=%.1f (want %.1f ±1.5) in-between=%d (want ≥1) released=%.1f (want rest)",
                         restWidth, heldWidth, restWidth * Theme.pressScale, between, released.last ?? 0))

        // Below the tiles, a strip down the left edge: section edges and headers
        // pass through it as they move, and the preview's "Start focus" and goal
        // bar show a recolour. Narrow, so it can be sampled every frame.
        let grid = tiles.dropFirst().reduce(teal) { $0.union($1) }
        let screen = window.convertToScreen(content.convert(content.bounds, to: nil))
        let strip = NSRect(x: grid.minX - 8, y: screen.minY, width: 60, height: grid.minY - 6 - screen.minY)
        func pick(_ name: String) async -> String {
            guard let tile = snap.accessibilityFrame(of: name, in: window) else { return "no tile \(name)" }
            let before = snap.fingerprint(of: strip, in: window)
            let point = window.convertPoint(fromScreen: NSPoint(x: tile.midX, y: tile.midY))
            snap.mouse(.leftMouseDown, at: point, in: window)
            snap.mouse(.leftMouseUp, at: point, in: window)
            let prints = await snap.sample(for: 0.6) { snap.fingerprint(of: strip, in: window) }
            return Self.steps(prints, before: before)
        }
        snap.note("Teal to Sage: \(await pick("Sage & Clay")) colorway=\(appearancePrefs.colorwayID) (want changed, in-between 0, sage)")
        snap.note("Sage to Custom: \(await pick("Custom")) colorway=\(appearancePrefs.colorwayID) (want changed, in-between ≥3, custom)")
        snap.note("Custom to Teal: \(await pick("Teal & Amber")) colorway=\(appearancePrefs.colorwayID) (want changed, in-between ≥3, teal)")
    }

    /// Allowing calendar access eases the calendar list in.
    private func checkCalendarListMotion(_ snap: DebugSnapshots) async {
        guard let fake = calendarSource as? FakeCalendarSource else {
            snap.note("calendar source=real: skipping (the self-check only runs on the fake)")
            return
        }
        seedCalendar(fake)
        fake.access = .notAsked
        calendarModel.refresh()
        showCalendarSettings()
        guard let window = windows.mainWindow, let content = window.contentView else {
            snap.note("no main window")
            return
        }
        window.setContentSize(NSSize(width: 760, height: 560))
        await snap.wait(0.8)
        guard let allow = snap.accessibilityFrame(of: "Allow Access…", in: window),
              let intro = snap.readable(in: window).first(where: { $0.text.hasPrefix("FocusNow can show") })?.frame else {
            snap.note("calendar pane: no Allow button (access=\(calendarModel.access))")
            return
        }
        let screen = window.convertToScreen(content.convert(content.bounds, to: nil))
        // A strip down the pane's left edge, under the button: the access line
        // and the calendars' checkboxes pass through it.
        let pane = NSRect(x: intro.minX - 8, y: screen.minY, width: 60, height: allow.minY - 4 - screen.minY)
        let before = snap.fingerprint(of: pane, in: window)
        let point = window.convertPoint(fromScreen: NSPoint(x: allow.midX, y: allow.midY))
        snap.mouse(.leftMouseDown, at: point, in: window)
        snap.mouse(.leftMouseUp, at: point, in: window)
        let prints = await snap.sample(for: 0.8) { snap.fingerprint(of: pane, in: window) }
        snap.note("calendar list after Allow: \(Self.steps(prints, before: before)) access=\(calendarModel.access) " +
            "(want changed, in-between ≥3, granted)")
        fake.access = .granted
        fake.simulateChange()
    }

    /// "moved 9.2 over 12 frames, settled 0.0": the furthest the left edge got
    /// from where it rests, in how many samples it was more than 1 pt away, and
    /// how far away the last sample is.
    static func shake(_ edges: [CGFloat?], rest: CGFloat?) -> String {
        guard let rest else { return "nothing drawn at rest" }
        let offsets = edges.compactMap { $0 }.map { abs($0 - rest) }
        guard let last = offsets.last else { return "nothing drawn" }
        return String(format: "moved %.1f over %d frames, settled %.1f",
                      offsets.max() ?? 0, offsets.filter { $0 > 1 }.count, last)
    }

    /// "changed, in-between 7 of 36 samples": whether the picture ended up different from
    /// `before`, and how many other pictures were seen on the way there.
    static func steps(_ prints: [Int?], before: Int?) -> String {
        let seen = prints.compactMap { $0 }
        guard let last = seen.last else { return "nothing drawn" }
        let between = Set(seen).subtracting([before, last].compactMap { $0 }).count
        return "\(last == before ? "unchanged" : "changed"), in-between \(between) of \(prints.count) samples"
    }
}

/// Text that shakes when `count` goes up, with Reduce Motion on.
@MainActor @Observable
private final class ShakeProbe {
    var count = 0
}

private struct ShakeProbeView: View {
    static let identifier = "shake-probe"
    let probe: ShakeProbe

    var body: some View {
        Text("40:00")
            .font(.system(size: 40, weight: .light))
            .accessibilityIdentifier(Self.identifier)
            .modifier(RejectShake(trigger: probe.count, distance: 9))
            .environment(\._accessibilityReduceMotion, true)
            .frame(width: 320, height: 160)
    }
}

extension DebugSnapshots {
    /// Calls `measure` about once a frame for `seconds` and returns what it saw.
    func sample<T>(for seconds: Double, _ measure: () -> T) async -> [T] {
        var seen: [T] = []
        let end = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < end {
            seen.append(measure())
            await wait(1.0 / 60)
        }
        return seen
    }

    /// One mouse event at `point` (window coordinates), straight to the window.
    func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) {
        guard let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        window.sendEvent(event)
    }

    /// What's drawn in `rect` (screen coordinates), against the colour of its
    /// top-left pixel: the left and right edges (screen x) of everything that
    /// differs, and how strongly the most different pixel differs (0–255).
    struct Drawing {
        var extent: ClosedRange<CGFloat>?
        var ink: Int
    }

    func drawing(in rect: NSRect, of window: NSWindow) -> Drawing? {
        guard let (rep, viewRect) = pixels(in: rect, of: window), let data = rep.bitmapData else { return nil }
        let step = rep.bitsPerPixel / 8, rowBytes = rep.bytesPerRow
        let background = (0..<step).map { data[$0] }
        var low = Int.max, high = Int.min, ink = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let p = data + y * rowBytes + x * step
                var difference = 0
                for i in 0..<step { difference = max(difference, abs(Int(p[i]) - Int(background[i]))) }
                ink = max(ink, difference)
                if difference > 8 {
                    low = min(low, x)
                    high = max(high, x)
                }
            }
        }
        let scale = CGFloat(rep.pixelsWide) / viewRect.width
        let extent = low <= high ? (rect.minX + CGFloat(low) / scale)...(rect.minX + CGFloat(high + 1) / scale) : nil
        return Drawing(extent: extent, ink: ink)
    }

    /// A fingerprint of everything drawn in `rect` (screen coordinates): equal
    /// fingerprints, the same picture.
    func fingerprint(of rect: NSRect, in window: NSWindow) -> Int? {
        guard let (rep, _) = pixels(in: rect, of: window), let data = rep.bitmapData else { return nil }
        var hasher = Hasher()
        hasher.combine(bytes: UnsafeRawBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
        return hasher.finalize()
    }

    /// The average colour drawn in `rect` (screen coordinates), in sRGB.
    func averageColour(of rect: NSRect, in window: NSWindow) -> SRGBColor? {
        guard let (rep, _) = pixels(in: rect, of: window) else { return nil }
        var sum = (r: 0.0, g: 0.0, b: 0.0), count = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                sum = (sum.r + c.redComponent, sum.g + c.greenComponent, sum.b + c.blueComponent)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return SRGBColor(red: sum.r / count, green: sum.g / count, blue: sum.b / count)
    }

    /// `rect` (screen coordinates) of the window's content as drawn now.
    private func pixels(in rect: NSRect, of window: NSWindow) -> (NSBitmapImageRep, NSRect)? {
        guard let view = window.contentView else { return nil }
        let viewRect = view.convert(window.convertFromScreen(rect), from: nil).intersection(view.bounds)
        guard !viewRect.isEmpty, let rep = view.bitmapImageRepForCachingDisplay(in: viewRect) else { return nil }
        view.cacheDisplay(in: viewRect, to: rep)
        return (rep, viewRect)
    }
}
