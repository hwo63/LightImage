import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Accelerate

public final class ImageEngine: @unchecked Sendable {
    private let cubeCache = NSCache<NSData, NSData>()
    private final class CachedPortrait {
        let analysis: PortraitAnalysis
        init(_ analysis: PortraitAnalysis) { self.analysis = analysis }
    }
    private let portraitCache: NSCache<CIImage, CachedPortrait> = {
        let cache = NSCache<CIImage, CachedPortrait>()
        cache.countLimit = 4
        return cache
    }()
    public let context: CIContext
    public static let rawExtensions: Set<String> = ["dng", "cr2", "cr3", "nef", "nrw", "arw", "raf", "orf", "rw2", "pef", "srw", "3fr", "iiq", "raw"]
    public static let extensions = rawExtensions.union(["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "avif"])
    public let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    public init() {
        context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .cacheIntermediates: false])
    }
    public func load(url: URL, maxDimension: CGFloat? = nil) throws -> CIImage {
        var image: CIImage?
        if Self.rawExtensions.contains(url.pathExtension.lowercased()) {
            image = CIRAWFilter(imageURL: url)?.outputImage
        } else if let maxDimension,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) { image = CIImage(cgImage: cg) }
        if image == nil { image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) }
        guard var image, image.extent.width > 0, image.extent.height > 0, !image.extent.isInfinite else {
            throw LightImageError.unreadableImage(url.lastPathComponent)
        }
        image = normalized(image)
        var originalLongEdge = max(image.extent.width, image.extent.height)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let w = properties[kCGImagePropertyPixelWidth as String] as? Double, let h = properties[kCGImagePropertyPixelHeight as String] as? Double {
            originalLongEdge = max(w,h)
        }
        if let maxDimension { image = resized(image, maxDimension: maxDimension) }
        image = image.settingProperties(["LightImageOriginalLongEdge": originalLongEdge])
        return image
    }
    public func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
    public func resized(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let scale = min(1, maxDimension / max(image.extent.width, image.extent.height))
        guard scale < 1 else { return image }
        return image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
    }
    public func analyzePortrait(_ source: CIImage) throws -> PortraitAnalysis {
        if let cached = portraitCache.object(forKey: source) { return cached.analysis }
        let image = try cgImage(resized(source, maxDimension: 2400))
        let result = try PortraitAnalysis.analyze(image)
        portraitCache.setObject(CachedPortrait(result), forKey: source)
        return result
    }
    public func render(_ source: CIImage, adjustments a: Adjustments, portrait: PortraitAnalysis? = nil,
                       unframed: Bool = false) throws -> CIImage {
        let originalLongEdge = source.properties["LightImageOriginalLongEdge"] as? Double ?? max(source.extent.width,source.extent.height)
        let pixelScale = max(source.extent.width,source.extent.height) / max(1,originalLongEdge)
        var image = try AdvancedEffects.reduceNoise(source, a, pixelScale: pixelScale)
        if a.hasPortraitEdits {
            let analysis = try portrait ?? (a.needsPortraitAnalysis ? analyzePortrait(source) : PortraitAnalysis(subjects: []))
            image = try PortraitEffects.apply(image, adjustments: a, analysis: analysis)
        }
        if a["Temperature"] != 0 || a["Tint"] != 0 || a["IncrementalTemperature"] != 0 || a["IncrementalTint"] != 0 {
            // JPEG relative WB sliders are not Kelvin / Core Image tint units.
            // Use a relative temperature scale, separate from absolute RAW WB.
            let temp = a["Temperature"] == 0 ? 6500 * pow(2, a["IncrementalTemperature"] / 200) : a["Temperature"]
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: temp, y: a["Tint"] + a["IncrementalTint"] * 0.5),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }
        if a["AutoTone"] > 0 { image = try AdvancedEffects.automaticTone(image, engine: self) }
        image = try AdvancedEffects.dehaze(image, amount: a["Dehaze"], engine: self)
        if a["Exposure2012"] != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: a["Exposure2012"]]) }
        let colorSettings = ColorTreatment.settings(from: a)
        if colorSettings.isEdited {
            let cube = colorCube(colorSettings)
            image = image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": ColorTreatment.dimension, "inputCubeData": cube])
        }
        if a["Vibrance"] != 0 { image = image.applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: a["Vibrance"] / 100]) }
        let sizeScale = max(image.extent.width, image.extent.height) / 2000
        let clarity = a["Clarity2012"] / 100
        if clarity != 0 {
            image = image.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 18 * sizeScale, kCIInputIntensityKey: clarity * 0.65]).cropped(to: source.extent)
        }
        let texture = a["Texture"] / 100
        if texture != 0 {
            image = image.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: max(0.5, 2 * sizeScale), kCIInputIntensityKey: texture * 0.65]).cropped(to: source.extent)
        }
        image = try AdvancedEffects.sharpen(image, a, pixelScale: pixelScale)
        image = try LocalMaskRenderer.apply(image, masks: a.localMasks ?? [])
        if unframed { return image }
        return try finishFrame(image, adjustments: a)
    }
    public func finishFrame(_ image: CIImage, adjustments: Adjustments) throws -> CIImage {
        try FilmEffects.apply(geometry(image, adjustments: adjustments), adjustments: adjustments)
    }
    public func geometry(_ source: CIImage, adjustments a: Adjustments) -> CIImage {
        var image = source
        let turns = ((a.rotation % 4) + 4) % 4
        if turns != 0 {
            image = normalized(image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2)))
        }
        if a.flipHorizontal == true || a.flipVertical == true {
            image = normalized(image.transformed(by: CGAffineTransform(scaleX: a.flipHorizontal == true ? -1 : 1,
                                                                      y: a.flipVertical == true ? -1 : 1)))
        }
        let straighten = min(max(a["LightImageStraighten"], -45), 45) * .pi / 180
        if straighten != 0 {
            let w = image.extent.width, h = image.extent.height
            let c = cos(straighten), s = abs(sin(straighten))
            // Fit a centered rectangle of the original aspect ratio inside the rotation.
            let scale = min(w / (w * c + h * s), h / (h * c + w * s))
            let rotated = normalized(image.transformed(by: CGAffineTransform(rotationAngle: -straighten)))
            let rw = max(1, floor(w * scale) - 4), rh = max(1, floor(h * scale) - 4)
            let x = (rotated.extent.midX - rw / 2).rounded()
            let y = (rotated.extent.midY - rh / 2).rounded()
            image = normalized(rotated.cropped(to: CGRect(x: x, y: y, width: rw, height: rh)))
        }
        let extent = image.extent
        let scale = a["PerspectiveScale"] / 100
        if scale != 1 || a["PerspectiveX"] != 0 || a["PerspectiveY"] != 0 {
            let dx = extent.width * ((1 - scale) / 2 + a["PerspectiveX"] / 100)
            let dy = extent.height * ((1 - scale) / 2 - a["PerspectiveY"] / 100)
            let canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
            image = image.transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy)).composited(over: canvas).cropped(to: extent)
        }
        var w = image.extent.width, h = image.extent.height
        if a.cropAspect > 0 {
            if w / h > a.cropAspect { w = h * a.cropAspect } else { h = w / a.cropAspect }
        }
        w *= min(max(a.cropScale, 0.1), 1); h *= min(max(a.cropScale, 0.1), 1)
        let x = (image.extent.width - w) * min(max(a.cropX, 0), 1)
        let y = (image.extent.height - h) * (1 - min(max(a.cropY, 0), 1))
        return normalized(image.cropped(to: CGRect(x: x, y: y, width: w, height: h).integral.intersection(image.extent)))
    }
    public func cgImage(_ image: CIImage) throws -> CGImage {
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw LightImageError.exportFailed("Không thể kết xuất ảnh.")
        }
        return cg
    }
    public func export(url: URL, adjustments: Adjustments, destination: URL, format: String, quality: Double = 0.95, maxDimension: CGFloat? = nil) throws {
        // Run the detector on the same oriented input used for the interactive preview.
        let portrait = try adjustments.needsPortraitAnalysis ? analyzePortrait(load(url: url, maxDimension: 2400)) : nil
        var result = try render(load(url: url), adjustments: adjustments, portrait: portrait)
        if let maxDimension, maxDimension > 0 { result = resized(result, maxDimension: maxDimension) }
        let type = format == "png" ? UTType.png : format == "tiff" ? UTType.tiff : UTType.jpeg
        // Render to a temporary sibling, then atomically replace the selected destination.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".lightimage-\(UUID().uuidString).\(format)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if format == "tiff" {
            try context.writeTIFFRepresentation(of: result, to: temporary, format: .RGBA16, colorSpace: colorSpace, options: [:])
        } else {
            let cg = try cgImage(result)
            guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, type.identifier as CFString, 1, nil) else { throw LightImageError.exportFailed(destination.lastPathComponent) }
            // Explicitly tag sRGB; an untagged JPEG can be interpreted using the
            // receiving editor's working profile instead of our output space.
            let properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImagePropertyOrientation: 1,
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifColorSpace: 1],
                kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGsRGBIntent: 0]
            ]
            CGImageDestinationAddImage(output, cg, properties as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw LightImageError.exportFailed(destination.lastPathComponent) }
        }
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
    public func histogram(_ image: CGImage) -> [[Double]] {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var bins = [[Double]](repeating: [Double](repeating: 0, count: 64), count: 3)
        for i in stride(from: 0, to: pixels.count, by: 4) { for c in 0..<3 { bins[c][Int(pixels[i + c]) / 4] += 1 } }
        let peak = max(1, bins.flatMap { $0 }.max() ?? 1)
        return bins.map { $0.map { pow($0 / peak, 0.55) } }
    }

    private func colorCube(_ a: Adjustments) -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let key = ((try? encoder.encode(a)) ?? Data()) as NSData
        if let cached = cubeCache.object(forKey: key) { return cached as Data }
        let data = ColorTreatment(a).makeCube()
        cubeCache.totalCostLimit = 32 * 1024 * 1024
        cubeCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
    /// Shape-preserving cubic Hermite interpolation: smooth joins without overshooting control points.
    public static func curve(_ value: Double, _ points: [CurvePoint]?) -> Double {
        guard let p = points, p.count >= 2, let first = p.first, let last = p.last else { return value }
        if value <= first.x { return first.y }; if value >= last.x { return last.y }
        func slope(_ i: Int) -> Double { (p[i+1].y-p[i].y) / max(1e-8,p[i+1].x-p[i].x) }
        func tangent(_ i: Int) -> Double {
            if i == 0 { return slope(0) }; if i == p.count-1 { return slope(i-1) }
            let d0 = slope(i-1), d1 = slope(i)
            guard d0*d1 > 0 else { return 0 }
            let h0 = p[i].x-p[i-1].x, h1 = p[i+1].x-p[i].x
            let w1 = 2*h1+h0, w2 = h1+2*h0
            return (w1+w2)/(w1/d0+w2/d1)
        }
        for i in 0..<(p.count-1) where value <= p[i+1].x {
            let h = p[i+1].x-p[i].x, t = (value-p[i].x)/h
            let y = (2*t*t*t-3*t*t+1)*p[i].y + (t*t*t-2*t*t+t)*h*tangent(i) + (-2*t*t*t+3*t*t)*p[i+1].y + (t*t*t-t*t)*h*tangent(i+1)
            return min(max(y,min(p[i].y,p[i+1].y)),max(p[i].y,p[i+1].y))
        }
        return value
    }
}
