import AppKit

// Renders the source art into Apple's macOS icon template: an 824×824 rounded-square body,
// centred on a 1024×1024 transparent canvas, with a soft drop shadow in the margin.
let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!
let outDir = args[2]

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185.4 * scale, yRadius: 185.4 * scale)

    // Shadow (only at sizes where it's visible).
    if pixels >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 22 * scale
        shadow.set()
        NSColor(calibratedRed: 0.87, green: 0.42, blue: 0.27, alpha: 1).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    source.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for s in scales {
        let name = s == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! render(pixels: points * s).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
print("ok")
