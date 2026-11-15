// Draws the app icon: a black square with three faint lines of text and a white cursor.
// Usage: swift icon/make_icon.swift <output.iconset>
import AppKit

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024  // design on a 1024 grid

    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s), xRadius: r * s, yRadius: r * s)
    }

    // Background square with a hairline edge, so it shows up on a dark Dock.
    let body = rounded(100, 100, 824, 824, 185)
    NSColor.black.setFill()
    body.fill()
    NSColor(white: 1, alpha: 0.15).setStroke()
    body.lineWidth = 4 * s
    body.stroke()

    // Three lines of "text".
    NSColor(white: 1, alpha: 0.28).setFill()
    for (i, width) in [520.0, 440.0, 300.0].enumerated() {
        rounded(252, 608 - CGFloat(i) * 110, width, 28, 14).fill()
    }

    // The cursor at the end of the last line.
    NSColor.white.setFill()
    rounded(588, 348, 20, 108, 10).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! png(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! png(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
