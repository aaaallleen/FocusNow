// Builds build/AppIcon.icns from icon.png.
// Usage: swift scripts/make-icon.swift [source.png] [output-dir]
//
// icon.png is a picture of an icon: a cream tile on a teal background with a
// long shadow. This crops to the cream tile, places it on the macOS icon grid
// (an 824 px rounded square centred on a 1024 px transparent canvas, with a soft
// drop shadow), and writes every iconset size.
import AppKit

let args = CommandLine.arguments
let source = URL(fileURLWithPath: args.count > 1 ? args[1] : "icon.png")
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "build")

// The cream tile spans about x 270–992, y 261–1010 (top-left pixel coordinates)
// with a corner radius of about 186 px. A centred 690 px square sits far enough
// inside that the clip's corners never reach the teal outside the tile.
let cropSize = 690
let cropCenter = CGPoint(x: 631, y: 636)
let cropRect = CGRect(
    x: Int(cropCenter.x) - cropSize / 2, y: Int(cropCenter.y) - cropSize / 2,
    width: cropSize, height: cropSize)

let canvas = 1024
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
      let full = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let cropped = full.cropping(to: cropRect) else {
    fatalError("could not read or crop \(source.path)")
}

func render(size: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / CGFloat(canvas)
    ctx.scaleBy(x: scale, y: scale)

    let path = CGPath(roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // The tile itself.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(cropped, in: tileRect)
    ctx.restoreGState()
    return ctx.makeImage()!
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
