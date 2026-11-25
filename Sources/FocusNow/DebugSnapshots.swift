import AppKit
import FocusNowCore
import SwiftUI

/// Development aid. When FOCUSNOW_SNAPSHOT_DIR is set, the app drives itself
/// through a script of steps, renders its own views to PNGs in that folder,
/// logs what each one shows to `log.txt`, then quits. It renders in-process,
/// so it needs no screen-recording permission. Never active in normal use.
@MainActor
final class DebugSnapshots {
    /// Only with a separate data folder too, so it never touches real history.
    static var directory: URL? {
        SelfCheckGate.directory(in: ProcessInfo.processInfo.environment)
    }

    private let dir: URL
    var directory: URL { dir }
    private var log: [String] = []

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func note(_ line: String) {
        log.append(line)
    }

    /// Renders `view` at `scale` over `background` (views drawn for the menu bar
    /// or a vibrant popover are transparent on their own).
    func capture(_ view: NSView, as name: String, background: NSColor = .windowBackgroundColor, scale: CGFloat = 2) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            note("\(name): could not capture (empty bounds \(view.bounds))")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let size = NSSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        let out = NSImage(size: size, flipped: false) { rect in
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                background.setFill()
                rect.fill()
            }
            rep.draw(in: rect)
            return true
        }
        guard let tiff = out.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Renders a SwiftUI view offscreen, in light or dark appearance.
    func render<V: View>(_ view: V, as name: String, dark: Bool = false) {
        let content = view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            note("\(name): render failed")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    // MARK: - Driving text fields and keys

    /// Editable text fields in `window`, top to bottom, then left to right.
    func textFields(in window: NSWindow) -> [NSTextField] {
        func walk(_ view: NSView) -> [NSTextField] {
            var found: [NSTextField] = []
            if let field = view as? NSTextField, field.isEditable, !field.isHiddenOrHasHiddenAncestor {
                found.append(field)
            }
            for sub in view.subviews { found += walk(sub) }
            return found
        }
        guard let root = window.contentView else { return [] }
        return walk(root).sorted {
            let a = $0.convert($0.bounds, to: nil), b = $1.convert($1.bounds, to: nil)
            return a.maxY != b.maxY ? a.maxY > b.maxY : a.minX < b.minX
        }
    }

    /// Focuses field `index`, selects its text and types `text` (no Return).
    func type(_ text: String, intoField index: Int, of window: NSWindow) async {
        let fields = textFields(in: window)
        guard fields.indices.contains(index) else {
            note("no text field \(index) (found \(fields.count))")
            return
        }
        window.makeFirstResponder(fields[index])
        await wait(0.15)
        (window.firstResponder as? NSText)?.selectAll(nil)
        for character in text { sendKey(String(character), keyCode: 0, to: window) }
        await wait(0.15)
    }

    /// Selects all in whatever field has focus and types `text` (no Return).
    func typeIntoFocusedField(_ text: String, in window: NSWindow) async {
        guard let editor = window.firstResponder as? NSText else {
            note("no focused field (first responder: \(String(describing: window.firstResponder)))")
            return
        }
        editor.selectAll(nil)
        for character in text { sendKey(String(character), keyCode: 0, to: window) }
        await wait(0.15)
    }

    /// An accessibility attribute read by key: SwiftUI's own elements answer the
    /// NSAccessibility messages but aren't NSAccessibilityProtocol in Swift.
    private static func attribute(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    /// Every element in `window`'s accessibility tree, breadth first.
    func accessibilityElements(in window: NSWindow) -> [NSObject] {
        guard let root = window.contentView else { return [] }
        var queue: [NSObject] = [root], found: [NSObject] = []
        while !queue.isEmpty, found.count < 5000 {
            let element = queue.removeFirst()
            found.append(element)
            queue += (Self.attribute(element, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject }
        }
        return found
    }

    /// Every element that reads something: its text (label, else title, else
    /// value), its accessibility identifier, and its screen frame.
    func readable(in window: NSWindow) -> [(text: String, identifier: String?, frame: NSRect)] {
        accessibilityElements(in: window).compactMap { element in
            let text = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                .compactMap { Self.attribute(element, $0) as? String }.first { !$0.isEmpty }
            guard let text, let frame = (Self.attribute(element, "accessibilityFrame") as? NSValue)?.rectValue
            else { return nil }
            return (text, Self.attribute(element, "accessibilityIdentifier") as? String, frame)
        }
    }

    /// Whether any element reads `text`: as its label, title or value (static
    /// text exposes its words as its value).
    func containsText(_ text: String, in window: NSWindow) -> Bool {
        accessibilityElements(in: window).contains { element in
            ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                .contains { Self.attribute(element, $0) as? String == text }
        }
    }

    /// The labels of the elements VoiceOver reads as selected.
    func selectedLabels(in window: NSWindow) -> [String] {
        accessibilityElements(in: window).compactMap { element in
            guard Self.attribute(element, "isAccessibilitySelected") as? Bool == true else { return nil }
            return Self.attribute(element, "accessibilityLabel") as? String
        }
    }

    /// The screen frame of the element with this accessibility label, title or identifier.
    func accessibilityFrame(of label: String, in window: NSWindow) -> NSRect? {
        let element = accessibilityElements(in: window).first {
            Self.attribute($0, "accessibilityLabel") as? String == label
                || Self.attribute($0, "accessibilityTitle") as? String == label
                || Self.attribute($0, "accessibilityIdentifier") as? String == label
        }
        return element.flatMap { (Self.attribute($0, "accessibilityFrame") as? NSValue)?.rectValue }
    }

    /// Does what a click on row `index` of the first list in `window` (a
    /// sidebar) does: focuses the list and selects the row. A posted click
    /// can't: macOS usually refuses to make the app active during a run, and a
    /// list in a window that isn't key ignores clicks.
    func selectRow(_ index: Int, in window: NSWindow) async {
        func walk(_ view: NSView) -> NSTableView? {
            (view as? NSTableView) ?? view.subviews.lazy.compactMap(walk).first
        }
        guard let list = window.contentView.flatMap(walk), index < list.numberOfRows else {
            note("no list row \(index)")
            return
        }
        window.makeFirstResponder(list)
        list.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        await wait(0.4)
    }

    /// What VoiceOver announces for the elements with these roles: `role "label"`,
    /// plus the hint when there is one.
    func spoken(roles: Set<String>, in window: NSWindow) -> [String] {
        accessibilityElements(in: window).compactMap { element in
            guard let role = Self.attribute(element, "accessibilityRole") as? String, roles.contains(role) else { return nil }
            // A stepper's own arrows: VoiceOver reads them as part of the stepper.
            let subrole = Self.attribute(element, "accessibilitySubrole") as? String
            if subrole == "AXIncrementArrow" || subrole == "AXDecrementArrow" { return nil }
            // A switch in a form is named by the text beside it, linked as its title element.
            let titleElement = Self.attribute(element, "accessibilityTitleUIElement") as? NSObject
            let label = [Self.attribute(element, "accessibilityLabel"), Self.attribute(element, "accessibilityTitle"),
                         titleElement.flatMap { Self.attribute($0, "accessibilityValue") }]
                .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            let help = Self.attribute(element, "accessibilityHelp") as? String
            return "\(role) \"\(label)\"" + (help.map { " hint=\"\($0)\"" } ?? "")
        }
    }

    /// Clicks the middle of the control with this accessibility label or
    /// identifier, found through the accessibility tree. Returns whether the
    /// control was found.
    func press(accessibilityLabel label: String, in window: NSWindow) async -> Bool {
        guard let frame = accessibilityFrame(of: label, in: window) else {
            note("no control labelled \"\(label)\"")
            return false
        }
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
        await wait(0.3)
        return true
    }

    /// Clicks `point` (window coordinates) through the app's event queue, the
    /// way a real click arrives, so event monitors see it too.
    func postClick(at point: NSPoint, in window: NSWindow) async {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        await wait(0.6)
    }

    /// One key press through the app's event queue, so event monitors see it.
    func postKey(_ keyCode: UInt16, characters: String, in window: NSWindow) async {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        await wait(0.6)
    }

    /// Clicks the up (or down) arrow of stepper `index`, top to bottom.
    func clickStepper(_ index: Int, up: Bool, in window: NSWindow) async {
        func walk(_ view: NSView) -> [NSStepper] {
            ((view as? NSStepper).map { [$0] } ?? []) + view.subviews.flatMap { walk($0) }
        }
        let steppers = (window.contentView.map(walk) ?? []).sorted {
            $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY
        }
        guard steppers.indices.contains(index) else {
            note("no stepper \(index) (found \(steppers.count))")
            return
        }
        let frame = steppers[index].convert(steppers[index].bounds, to: nil)
        let point = NSPoint(x: frame.midX, y: up ? frame.maxY - frame.height / 4 : frame.minY + frame.height / 4)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
        await wait(0.3)
    }

    /// One key press: 36 is Return ("\r"), 53 is Escape ("\u{1b}").
    func pressKey(_ keyCode: UInt16, characters: String, in window: NSWindow) async {
        sendKey(characters, keyCode: keyCode, to: window)
        await wait(0.2)
    }

    func sendKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], to window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode) else { continue }
            window.sendEvent(event)
        }
    }

    func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func finish() {
        try? log.joined(separator: "\n").appending("\n").write(
            to: dir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Describes the menu bar button for the log.
    static func describe(_ button: NSStatusBarButton?) -> String {
        guard let button else { return "no button" }
        let symbol = button.image?.accessibilityDescription ?? button.image?.name() ?? "image"
        return "title=\"\(button.attributedTitle.string)\" image=\(symbol) dimmed=\(button.appearsDisabled) " +
            "alpha=\(String(format: "%.2f", button.alphaValue))"
    }
}
