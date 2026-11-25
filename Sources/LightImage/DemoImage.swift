import AppKit
import ImageIO
import UniformTypeIdentifiers

enum DemoImage {
    static func write(to url: URL) throws {
        let width = 2400, height = 1600
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        let sky = CGGradient(colorsSpace: space, colors: [color(0.93, 0.76, 0.57), color(0.68, 0.77, 0.78), color(0.29, 0.46, 0.53)] as CFArray, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 500), end: CGPoint(x: 0, y: 1600), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let sun = CGRect(x: 1670, y: 1040, width: 180, height: 180)
        ctx.setFillColor(color(1, 0.9, 0.69)); ctx.fillEllipse(in: sun)
        func ridge(_ points: [CGPoint], _ fill: CGColor) {
            ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: 0)); points.forEach { ctx.addLine(to: $0) }
            ctx.addLine(to: CGPoint(x: 2400, y: 0)); ctx.closePath(); ctx.setFillColor(fill); ctx.fillPath()
        }
        ridge([.init(x: 0, y: 780), .init(x: 350, y: 1160), .init(x: 580, y: 960), .init(x: 910, y: 1400), .init(x: 1220, y: 1030), .init(x: 1460, y: 1260), .init(x: 1850, y: 860), .init(x: 2200, y: 1120), .init(x: 2400, y: 940)], color(0.44, 0.54, 0.56))
        ridge([.init(x: 0, y: 680), .init(x: 400, y: 910), .init(x: 720, y: 720), .init(x: 1080, y: 1000), .init(x: 1480, y: 680), .init(x: 1910, y: 1030), .init(x: 2400, y: 720)], color(0.23, 0.39, 0.41))
        // Snow on the highest ridge.
        ctx.beginPath(); ctx.move(to: .init(x: 910, y: 1400)); ctx.addLines(between: [.init(x: 770, y: 1214), .init(x: 875, y: 1250), .init(x: 910, y: 1190), .init(x: 950, y: 1280), .init(x: 1035, y: 1250)])
        ctx.closePath(); ctx.setFillColor(color(0.84, 0.84, 0.76)); ctx.fillPath()
        let lake = CGGradient(colorsSpace: space, colors: [color(0.1, 0.3, 0.32), color(0.46, 0.61, 0.56)] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: 0, width: 2400, height: 620))
        ctx.drawLinearGradient(lake, start: .zero, end: CGPoint(x: 0, y: 620), options: []); ctx.restoreGState()
        for i in 0..<130 {
            let y = CGFloat(i) * 4.5 + 20
            let x = CGFloat((i * 137) % 2300)
            ctx.setStrokeColor(CGColor(srgbRed: 0.7, green: 0.76, blue: 0.6, alpha: 0.15))
            ctx.setLineWidth(1.2); ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + CGFloat(50 + i % 210), y: y)); ctx.strokePath()
        }
        ridge([.init(x: 0, y: 520), .init(x: 260, y: 440), .init(x: 480, y: 290), .init(x: 780, y: 200), .init(x: 1200, y: 110), .init(x: 1800, y: 60), .init(x: 2400, y: 0)], color(0.18, 0.27, 0.22))
        func pine(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
            ctx.setFillColor(color(0.09, 0.19, 0.18)); ctx.fill(CGRect(x: x - size * 0.025, y: y, width: size * 0.05, height: size))
            for j in 0..<4 {
                let base = y + size * (0.2 + CGFloat(j) * 0.15), half = size * (0.27 - CGFloat(j) * 0.045)
                ctx.beginPath(); ctx.move(to: CGPoint(x: x - half, y: base)); ctx.addLine(to: CGPoint(x: x, y: base + size * 0.47)); ctx.addLine(to: CGPoint(x: x + half, y: base)); ctx.closePath(); ctx.fillPath()
            }
        }
        for i in 0..<45 { pine(CGFloat(i * 23), CGFloat(340 - i * 5), CGFloat(130 + (i * 47) % 250)) }
        pine(100, 180, 640); pine(220, 200, 480)
        ctx.setFillColor(color(0.63, 0.37, 0.19)); ctx.fill(CGRect(x: 1450, y: 500, width: 200, height: 95))
        ctx.beginPath(); ctx.move(to: CGPoint(x: 1420, y: 595)); ctx.addLine(to: CGPoint(x: 1550, y: 690)); ctx.addLine(to: CGPoint(x: 1680, y: 595)); ctx.closePath(); ctx.setFillColor(color(0.18, 0.22, 0.2)); ctx.fillPath()
        ctx.setFillColor(color(0.98, 0.76, 0.4)); ctx.fill(CGRect(x: 1485, y: 535, width: 33, height: 32)); ctx.fill(CGRect(x: 1575, y: 535, width: 33, height: 32))
        guard let image = ctx.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.97] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
