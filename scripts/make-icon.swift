import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let p = CGFloat(pixels)
    let rect = NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9, height: p * 0.9)
    let shape = NSBezierPath(roundedRect: rect, xRadius: p * 0.21, yRadius: p * 0.21)
    NSGradient(starting: NSColor(srgbRed: 0.2, green: 0.25, blue: 0.22, alpha: 1), ending: NSColor(srgbRed: 0.06, green: 0.1, blue: 0.09, alpha: 1))!.draw(in: shape, angle: -70)
    NSColor(srgbRed: 0.78, green: 0.9, blue: 0.57, alpha: 1).setStroke()
    let circle = NSBezierPath(ovalIn: NSRect(x: p * 0.23, y: p * 0.23, width: p * 0.54, height: p * 0.54)); circle.lineWidth = p * 0.022; circle.stroke()
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3
        let a = CGPoint(x: p * (0.5 + 0.135 * cos(angle)), y: p * (0.5 + 0.135 * sin(angle)))
        let b = CGPoint(x: p * (0.5 + 0.135 * cos(angle + .pi / 3)), y: p * (0.5 + 0.135 * sin(angle + .pi / 3)))
        let c = CGPoint(x: p * (0.5 + 0.265 * cos(angle + .pi / 2)), y: p * (0.5 + 0.265 * sin(angle + .pi / 2)))
        let blade = NSBezierPath(); blade.move(to: a); blade.line(to: b); blade.line(to: c); blade.lineWidth = p * 0.018; blade.lineCapStyle = .round; blade.lineJoinStyle = .round; blade.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
}
