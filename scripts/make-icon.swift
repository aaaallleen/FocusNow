// Builds build/AppIcon.icns from the icon SVG.
// Usage: swift scripts/make-icon.swift [source.svg] [output-dir]
//        (defaults: Resources/Icon/icon.svg, build)
//
// The SVG is the whole icon: a rounded tile with the hourglass on it. AppKit
// draws it onto the macOS icon grid (an 824 px square centred on a 1024 px
// transparent canvas) with a soft drop shadow that follows the tile's own
// outline, and every iconset size is written from that.
import AppKit

let args = CommandLine.arguments
let source = URL(fileURLWithPath: args.count > 1 ? args[1] : "Resources/Icon/icon.svg")
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "build")

guard let svg = NSImage(contentsOf: source), svg.isValid else {
    fatalError("could not read \(source.path) (copy icon.svg into Resources/Icon/)")
}

let canvas = 1024
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)

func render(size: Int) -> CGImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(size) / CGFloat(canvas)
    context.cgContext.scaleBy(x: scale, y: scale)

    // The shadow is set while the tile draws, so it follows the tile's outline.
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.set()
    svg.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(icns.path)")
