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

    /// Clicks the middle of the control with this accessibility label, found
    /// through the accessibility tree (SwiftUI's own elements answer the
    /// NSAccessibility messages but aren't NSAccessibilityProtocol in Swift,
    /// so they're read by key). Returns whether the control was found.
    func press(accessibilityLabel label: String, in window: NSWindow) async -> Bool {
        func value(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        guard let root = window.contentView else { return false }
        var queue: [NSObject] = [root]
        var frame: NSRect?
        var visited = 0
        while !queue.isEmpty, visited < 5000 {
            let element = queue.removeFirst()
            visited += 1
            if value(element, "accessibilityLabel") as? String == label {
                frame = (value(element, "accessibilityFrame") as? NSValue)?.rectValue
                break
            }
            queue += (value(element, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject }
        }
        guard let frame else {
            note("no control labelled \"\(label)\" (\(visited) elements)")
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
