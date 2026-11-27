import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

extension ImageEngine {
    /// Store the selection itself so changing sliders, reopening the catalog,
    /// and exporting never has to run the detector again.
    public func detectMask(_ kind: LocalMask.Kind, in source: CIImage) throws -> Data {
        let image = try cgImage(resized(source, maxDimension: kind == .sky ? 640 : 1200))
        let mask: CGImage
        switch kind {
        case .sky:
            mask = try SkyMask.detect(in: image)
        case .subject, .background:
            mask = try foregroundMask(in: image)
        default:
            throw AutomaticMaskError.unavailable
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AutomaticMaskError.unavailable
        }
        CGImageDestinationAddImage(destination, mask, nil)
        guard CGImageDestinationFinalize(destination) else { throw AutomaticMaskError.unavailable }
        return data as Data
    }

    private func foregroundMask(in image: CGImage) throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw AutomaticMaskError.noSubject
        }
        let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let mask = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        guard let result = context.createCGImage(mask, from: mask.extent, format: .L8,
                                                 colorSpace: CGColorSpaceCreateDeviceGray()) else {
            throw AutomaticMaskError.unavailable
        }
        return result
    }

    public func automaticMaskOverlay(_ mask: LocalMask) throws -> CGImage {
        guard let bitmap = mask.automaticBitmap,
              let colorize = Self.maskOverlayKernel else { throw AutomaticMaskError.unavailable }
        let scale = mask.strokes.isEmpty ? 1 : max(1, 1200 / max(bitmap.extent.width, bitmap.extent.height))
        let extent = bitmap.extent.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
        guard let coverage = LocalMaskRenderer.automaticCoverage(mask, extent: extent),
              let overlay = colorize.apply(extent: coverage.extent, arguments: [coverage, mask.inverted ? 1.0 : 0.0]) else {
            throw AutomaticMaskError.unavailable
        }
        return try cgImage(overlay)
    }

    private static let maskOverlayKernel = CIColorKernel(source: """
        kernel vec4 showMask(__sample mask, float invert) {
            float alpha = 0.48 * mix(mask.r, 1.0 - mask.r, invert);
            return vec4(vec3(1.0, 0.21, 0.40) * alpha, alpha);
        }
        """)
}

enum AutomaticMaskError: LocalizedError {
    case noSky, noSubject, unavailable

    var errorDescription: String? {
        switch self {
        case .noSky: return tr("Chưa tìm thấy vùng trời đủ rõ trong ảnh.")
        case .noSubject: return tr("Chưa tìm thấy chủ thể đủ rõ để tách khỏi hậu cảnh.")
        case .unavailable: return tr("Không thể tạo mặt nạ tự động cho ảnh này.")
        }
    }
}

enum SkyMask {
    static func detect(in image: CGImage) throws -> CGImage {
        let width = image.width, height = image.height
        let count = width * height
        guard width >= 8, height >= 8 else { throw AutomaticMaskError.noSky }
        var rgba = [UInt8](repeating: 0, count: count * 4)
        let loaded = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard loaded else { throw AutomaticMaskError.unavailable }

        // Sky usually connects to the top of the frame. Combine color with
        // edge and texture cues so a blue object lower in the scene isn't selected.
        let luma = (0..<count).map { i -> Float in
            let index = i * 4
            return (0.2126 * Float(rgba[index]) + 0.7152 * Float(rgba[index + 1]) + 0.0722 * Float(rgba[index + 2])) / 255
        }
        var strength = [Float](repeating: 0, count: count)
        var seeds = [Bool](repeating: false, count: count)
        func smooth(_ lo: Float, _ hi: Float, _ value: Float) -> Float {
            let t = min(max((value - lo) / (hi - lo), 0), 1)
            return t * t * (3 - 2 * t)
        }
        for y in 0..<Int(Double(height) * 0.87) {
            let relativeY = Float(y) / Float(height)
            for x in 0..<width {
                let i = y * width + x, px = i * 4
                guard rgba[px + 3] > 240 else { continue }
                let r = Float(rgba[px]) / 255, g = Float(rgba[px + 1]) / 255, b = Float(rgba[px + 2]) / 255
                let luminance = luma[i]
                let chroma = max(r, g, b) - min(r, g, b)
                let blue = smooth(0.025, 0.12, b - r) * smooth(-0.04, 0.04, b - g)
                    * smooth(0.12, 0.30, luminance)
                let gray = (1 - smooth(0.07, 0.18, chroma)) * smooth(0.44, 0.72, luminance)
                let warm = smooth(0.06, 0.20, r - b) * smooth(0.025, 0.10, r - g)
                    * smooth(0.32, 0.57, luminance) * (1 - smooth(0.23, 0.78, relativeY))
                let step = max(1, width / 260)
                let horizontal = abs(luma[y * width + min(x + step, width - 1)] - luma[y * width + max(x - step, 0)])
                let vertical = abs(luma[min(y + step, height - 1) * width + x] - luma[max(y - step, 0) * width + x])
                let texture = 1 - smooth(0.06, 0.33, max(horizontal, vertical))
                let color = max(blue, gray, warm * 0.92)
                strength[i] = color * (0.46 + 0.54 * texture)
                if relativeY < 0.055, strength[i] > 0.60 {
                    // Bright neutral clouds can seed a mask, with a higher
                    // threshold to avoid selecting dim walls and highlights.
                    seeds[i] = blue > 0.59 || warm > 0.70 || (gray > 0.85 && texture > 0.70)
                }
            }
        }

        var visited = [Bool](repeating: false, count: count)
        var alpha = [UInt8](repeating: 0, count: count)
        var queue: [Int] = []
        let minimumComponent = max(12, count / 1300)
        func colorDistance(_ a: Int, _ b: Int) -> Int {
            let p = a * 4, q = b * 4
            return abs(Int(rgba[p]) - Int(rgba[q])) +
                abs(Int(rgba[p + 1]) - Int(rgba[q + 1])) +
                abs(Int(rgba[p + 2]) - Int(rgba[q + 2]))
        }
        for seed in 0..<count where seeds[seed] && !visited[seed] {
            queue.removeAll(keepingCapacity: true)
            queue.append(seed)
            visited[seed] = true
            var head = 0
            while head < queue.count {
                let pixel = queue[head]; head += 1
                let x = pixel % width, y = pixel / width
                func add(_ index: Int, ahead: Int) {
                    // Compare across the edge as well as the next pixel. This
                    // prevents the fill crossing antialiased ridges and buildings
                    // whose colors otherwise resemble the sky.
                    if !visited[index] && strength[index] > 0.45 &&
                        colorDistance(pixel, index) < 27 && colorDistance(pixel, ahead) < 49 {
                        queue.append(index); visited[index] = true
                    }
                }
                if x > 0 { add(pixel - 1, ahead: pixel - min(x, 2)) }
                if x < width - 1 { add(pixel + 1, ahead: pixel + min(width - 1 - x, 2)) }
                if y > 0 { add(pixel - width, ahead: pixel - min(y, 2) * width) }
                if y < height - 1 { add(pixel + width, ahead: pixel + min(height - 1 - y, 2) * width) }
            }
            guard queue.count >= minimumComponent else { continue }
            for i in queue { alpha[i] = UInt8((255 * smooth(0.32, 0.62, strength[i])).rounded()) }
        }
        guard alpha.lazy.filter({ $0 > 128 }).count >= max(24, count / 500),
              let data = CGDataProvider(data: Data(alpha) as CFData),
              let mask = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                 bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                 provider: data, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw AutomaticMaskError.noSky
        }
        return mask
    }
}
