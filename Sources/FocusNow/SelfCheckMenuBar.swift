import AppKit
import FocusNowCore

/// The self-check's menubar phase: where the glyph (and the countdown) sit in
/// the menu bar button, measured from what the button actually draws.
extension AppDelegate {
    func checkMenuBar(_ snap: DebugSnapshots) async {
        snap.note("== menubar ==")
        engine.cancel()
        engine.skipBreak()
        closeAllWindows()
        await snap.wait(0.4)

        func measure(_ label: String) {
            guard let button = statusItem.button,
                  let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
                snap.note("\(label): no button")
                return
            }
            button.cacheDisplay(in: button.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: snap.directory.appendingPathComponent("menubar-\(label).png"))
            }
            let (w, h) = (rep.pixelsWide, rep.pixelsHigh)
            let scale = CGFloat(w) / max(button.bounds.width, 1)
            // Columns and rows that draw anything, then the first cluster of columns (the glyph).
            var columns = [Bool](repeating: false, count: w)
            for x in 0..<w {
                for y in 0..<h where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15 {
                    columns[x] = true
                    break
                }
            }
            guard let first = columns.firstIndex(of: true) else {
                snap.note("\(label): nothing drawn")
                return
            }
            var glyphEnd = first
            while glyphEnd + 1 < w, columns[glyphEnd + 1] { glyphEnd += 1 }
            let last = columns.lastIndex(of: true)!
            func rows(in range: ClosedRange<Int>) -> (Int, Int)? {
                var top: Int?, bottom: Int?
                for y in 0..<h {
                    for x in range where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15 {
                        if top == nil { top = y }
                        bottom = y
                        break
                    }
                }
                return top.flatMap { t in bottom.map { (t, $0) } }
            }
            func pt(_ px: Int) -> String { String(format: "%.1f", CGFloat(px) / scale) }
            func ptf(_ v: CGFloat) -> String { String(format: "%.1f", v / scale) }
            let glyphRows = rows(in: first...glyphEnd)
            let left = CGFloat(first), right = CGFloat(w - 1 - last)
            var line = "\(label): button=\(Int(button.bounds.width))x\(Int(button.bounds.height)) " +
                "glyph x=\(pt(first))–\(pt(glyphEnd + 1)) content x=\(pt(first))–\(pt(last + 1)) " +
                "margins left=\(pt(Int(left))) right=\(pt(Int(right))) (centred when equal)"
            if let (top, bottom) = glyphRows {
                let above = CGFloat(top), below = CGFloat(h - 1 - bottom)
                line += " glyph y top=\(pt(top)) gapAbove=\(ptf(above)) gapBelow=\(ptf(below)) (centred when equal)"
            }
            if glyphEnd < last, let (top, bottom) = rows(in: (glyphEnd + 1)...last) {
                line += " text gapAbove=\(pt(top)) gapBelow=\(pt(h - 1 - bottom))"
            }
            // Centres in the bar, in points from the bar's top. The button can be
            // taller than the bar and hang over its edges (frame.maxY > bar height).
            let buttonTop = (button.superview?.bounds.height ?? 0) - button.frame.maxY
            let barCentre = (button.superview?.bounds.height ?? 0) / 2
            func centre(_ rows: (Int, Int)) -> CGFloat { buttonTop + CGFloat(rows.0 + rows.1 + 1) / 2 / scale }
            if let glyph = glyphRows {
                var centring = String(format: " glyphOffset=%.1f", centre(glyph) - barCentre)
                if glyphEnd < last, let text = rows(in: (glyphEnd + 1)...last) {
                    centring += String(format: " textOffsetFromGlyph=%.1f", centre(text) - centre(glyph))
                }
                snap.note("\(label) centring:\(centring) (want each within ±0.5)")
            }
            let frame = button.frame, bar = button.superview?.bounds ?? .zero, win = button.window?.frame ?? .zero
            line += String(format: " | frame y=%.1f h=%.1f in superview h=%.1f window h=%.1f thickness=%.1f",
                           frame.minY, frame.height, bar.height, win.height, NSStatusBar.system.thickness)
            snap.note(line)
        }

        measure("idle")
        engine.start()
        await snap.wait(1.2)
        measure("focus")
        engine.pause()
        await snap.wait(0.4)
        measure("paused")
        engine.cancel()
        engine.nextFocusSecondsOverride = 2
        engine.start()
        await snap.wait(3.0)
        engine.nextFocusSecondsOverride = nil
        engine.acknowledge()
        statusItem.closePopover()
        engine.start()
        await snap.wait(1.2)
        measure("break")
        engine.cancel()
        engine.skipBreak()
        await snap.wait(0.4)
        measure("idle-after")
    }
}
