import AppKit
import FocusNowCore

/// Development aid. When FOCUSNOW_SNAPSHOT_DIR is set, the app drives itself
/// through a script of steps, renders its own views to PNGs in that folder,
/// logs what each one shows to `log.txt`, then quits. It renders in-process,
/// so it needs no screen-recording permission. Never active in normal use.
@MainActor
final class DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["FOCUSNOW_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private let dir: URL
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
