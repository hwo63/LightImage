import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A cropped grayscale selection, in the same bottom-left image coordinates
/// as brush strokes. Saving it keeps the result fixed across renders.
public struct BrushEdgeSelection: Codable, Equatable, Sendable {
    let bounds: CGRect
    let png: Data

    var image: CGImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Higher sensitivity stops at smaller changes in color.
    public static func detect(in image: CGImage, stroke: LocalMask.BrushStroke,
                              sensitivity: Double = 50) throws -> Self {
        guard let first = stroke.points.first else { throw AutomaticMaskError.unavailable }
        let scale = min(1, 2048 / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let radius = max(1, stroke.radius * Double(max(width, height)))
        let pixels = stroke.points.map { CGPoint(x: $0.x * Double(width), y: (1 - $0.y) * Double(height)) }
        let line = CGMutablePath()
        line.move(to: pixels[0])
        for point in pixels.dropFirst() { line.addLine(to: point) }
        let footprint: CGPath
        if stroke.points.allSatisfy({ $0 == first }) {
            let p = pixels[0]
            footprint = CGPath(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        } else {
            footprint = line.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }

        let patch = footprint.boundingBoxOfPath.insetBy(dx: -2, dy: -2).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !patch.isEmpty else { throw AutomaticMaskError.unavailable }
        let w = Int(patch.width), h = Int(patch.height)

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let read = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: -patch.minX, y: patch.maxY - Double(height), width: Double(width), height: Double(height)))
            return true
        }
        var eligible = [UInt8](repeating: 0, count: w * h)
        let drewFootprint = eligible.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.translateBy(x: -patch.minX, y: patch.maxY)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(footprint)
            context.fillPath()
            return true
        }
        guard read, drewFootprint else { throw AutomaticMaskError.unavailable }

        // Seed every pixel along the centerline. Grow outwards through pixels
        // connected to the stroke, rejecting sharp edges and color drift.
        var seeds = [Int32](repeating: -1, count: w * h)
        var queue: [Int32] = []
        func seed(_ p: CGPoint) {
            let x = min(max(Int(floor(p.x - patch.minX)), 0), w - 1)
            let y = min(max(Int(floor(p.y - patch.minY)), 0), h - 1)
            let i = y * w + x
            guard eligible[i] > 0, rgba[i * 4 + 3] > 16, seeds[i] < 0 else { return }
            seeds[i] = Int32(i)
            queue.append(Int32(i))
        }
        seed(pixels[0])
        for (a, b) in zip(pixels, pixels.dropFirst()) {
            let length = max(abs(b.x - a.x), abs(b.y - a.y))
            let steps = max(1, Int(ceil(length)))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                seed(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }

        func distance(_ a: Int, _ b: Int) -> Int {
            let p = a * 4, q = b * 4
            return abs(Int(rgba[p]) - Int(rgba[q])) +
                abs(Int(rgba[p + 1]) - Int(rgba[q + 1])) +
                abs(Int(rgba[p + 2]) - Int(rgba[q + 2]))
        }

        let level = sensitivity.isFinite ? min(max(sensitivity, 0), 100) / 100 : 0.5
        // At 50%, keep the original tolerances of 64 and 98.
        let neighborTolerance = Int((120 - 112 * level).rounded())
        let seedTolerance = Int((180 - 164 * level).rounded())
        var head = 0
        while head < queue.count {
            let i = Int(queue[head])
            head += 1
            let root = Int(seeds[i])
            func visit(_ next: Int) {
                guard eligible[next] > 0, seeds[next] < 0, rgba[next * 4 + 3] > 16,
                      distance(i, next) <= neighborTolerance,
                      distance(root, next) <= seedTolerance else { return }
                seeds[next] = Int32(root)
                queue.append(Int32(next))
            }
            let x = i % w
            if x > 0 { visit(i - 1) }
            if x < w - 1 { visit(i + 1) }
            if i >= w { visit(i - w) }
            if i + w < seeds.count { visit(i + w) }
        }

        // The brush itself supplies the falloff. Store just the edge gate.
        let selected = Data(seeds.map { $0 >= 0 ? UInt8(255) : 0 })
        guard let provider = CGDataProvider(data: selected as CFData),
              let gate = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw AutomaticMaskError.unavailable
        }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            throw AutomaticMaskError.unavailable
        }
        CGImageDestinationAddImage(destination, gate, nil)
        guard CGImageDestinationFinalize(destination) else { throw AutomaticMaskError.unavailable }
        let bounds = CGRect(x: patch.minX / Double(width), y: 1 - patch.maxY / Double(height),
                            width: patch.width / Double(width), height: patch.height / Double(height))
        return Self(bounds: bounds, png: png as Data)
    }
}
