import CoreImage

public struct LocalMask: Codable, Equatable, Identifiable, Sendable {
    public static let maximumCount = 16

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case sky, subject, background, linear, radial, brush

        public var isAutomatic: Bool {
            self == .sky || self == .subject || self == .background
        }

        public var supportsBrush: Bool { self == .brush || isAutomatic }
    }

    public enum Purpose: String, Codable, Sendable {
        case hair
    }

    public var id = UUID()
    public var kind: Kind
    public var purpose: Purpose?
    public var start = CGPoint(x: 0.5, y: 0.65)
    public var end = CGPoint(x: 0.5, y: 0.40)
    public var strokes: [BrushStroke] = []
    public var feather = 65.0
    public var opacity = 100.0
    public var enabled = true
    public var inverted = false
    public var exposure = 0.0
    public var contrast = 0.0
    public var saturation = 0.0
    public var temperature = 0.0
    private var hue: Double?
    public var automaticPNG: Data?

    public init(kind: Kind) { self.kind = kind }

    public var hasShape: Bool {
        if kind.isAutomatic { return automaticPNG?.isEmpty == false }
        return kind == .brush ? strokes.contains { !$0.points.isEmpty && !$0.erases } : start != end
    }

    public var hueRotation: Double {
        get { hue ?? 0 }
        set { hue = newValue == 0 ? nil : newValue }
    }

    var automaticBitmap: CIImage? {
        guard let automaticPNG else { return nil }
        return CIImage(data: automaticPNG, options: [.colorSpace: NSNull()])
    }

    var isActive: Bool {
        enabled && hasShape && opacity > 0 &&
            (exposure != 0 || contrast != 0 || saturation != 0 || temperature != 0 || hueRotation != 0)
    }

    public struct BrushStroke: Codable, Equatable, Sendable {
        public var points: [CGPoint]
        public let radius: Double
        public let erases: Bool
        public let softness: Double?
        public let strength: Double?
        public var edgeSelection: BrushEdgeSelection?

        /// Softness and strength are percentages. Missing values retain the
        /// brush behavior used by older catalogs.
        public init(points: [CGPoint], radius: Double, erases: Bool,
                    softness: Double? = nil, strength: Double? = nil) {
            self.points = points
            self.radius = radius
            self.erases = erases
            self.softness = softness
            self.strength = strength
        }
    }
}

enum LocalMaskRenderer {
    private static let gradient = CIColorKernel(source: """
        kernel vec4 localGradient(vec2 start, vec2 vector, float radial, float feather) {
            vec2 offset = destCoord() - start;
            float fraction = radial > 0.5 ? length(offset) / length(vector)
                                         : dot(offset, vector) / dot(vector, vector);
            float alpha = 1.0 - smoothstep(0.0, 1.0, fraction);
            if (radial > 0.5) alpha = 1.0 - smoothstep(1.0 - feather, 1.0, fraction);
            return vec4(vec3(alpha), 1.0);
        }
        """)

    private static let mix = CIColorKernel(source: """
        kernel vec4 localMix(__sample image, __sample effect, __sample mask, float amount, float invert) {
            float coverage = clamp(mask.r, 0.0, 1.0);
            return mix(image, effect, amount * mix(coverage, 1.0 - coverage, invert));
        }
        """)

    static func apply(_ image: CIImage, masks: [LocalMask]) throws -> CIImage {
        var result = image
        for mask in masks where mask.isActive {
            let extent = result.extent
            guard let coverage = coverage(mask, extent: extent) else {
                throw LightImageError.exportFailed(tr("Không thể tạo vùng mặt nạ."))
            }
            var effect = result
            if mask.hueRotation != 0 {
                effect = effect.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: mask.hueRotation * .pi / 180])
            }
            if mask.temperature != 0 {
                effect = effect.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500 * pow(2, mask.temperature / 200), y: 0),
                    "inputTargetNeutral": CIVector(x: 6500, y: 0)
                ])
            }
            if mask.exposure != 0 {
                effect = effect.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: mask.exposure])
            }
            if mask.saturation != 0 || mask.contrast != 0 {
                effect = effect.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 + mask.saturation / 100,
                    kCIInputContrastKey: 1 + mask.contrast / 150
                ])
            }
            guard let composited = mix?.apply(extent: extent, arguments: [
                result, effect, coverage, mask.opacity / 100, mask.inverted ? 1.0 : 0.0
            ]) else { throw LightImageError.exportFailed(tr("Không thể kết xuất mặt nạ.")) }
            result = composited
        }
        return result
    }

    private static func coverage(_ mask: LocalMask, extent: CGRect) -> CIImage? {
        if mask.kind.isAutomatic { return automaticCoverage(mask, extent: extent) }
        if mask.kind == .brush { return brush(mask, extent: extent) }
        let start = CGPoint(x: extent.minX + mask.start.x * extent.width,
                            y: extent.minY + mask.start.y * extent.height)
        let vector = CGPoint(x: (mask.end.x - mask.start.x) * extent.width,
                             y: (mask.end.y - mask.start.y) * extent.height)
        guard hypot(vector.x, vector.y) > 0.01 else { return nil }
        return gradient?.apply(extent: extent, arguments: [
            CIVector(cgPoint: start), CIVector(cgPoint: vector),
            mask.kind == .radial ? 1.0 : 0.0, max(0.01, mask.feather / 100)
        ])
    }

    static func automaticCoverage(_ mask: LocalMask, extent: CGRect) -> CIImage? {
        guard let bitmap = mask.automaticBitmap, bitmap.extent.width > 0, bitmap.extent.height > 0 else { return nil }
        let feather = max(0, min(1, mask.feather / 100))
        let radius = max(bitmap.extent.width, bitmap.extent.height) * 0.008 * feather
        var coverage = bitmap
        if radius > 0 {
            coverage = bitmap.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: bitmap.extent)
        }
        if mask.kind == .background { coverage = coverage.applyingFilter("CIColorInvert") }
        let base = coverage.transformed(by: CGAffineTransform(a: extent.width / bitmap.extent.width, b: 0, c: 0,
            d: extent.height / bitmap.extent.height, tx: extent.minX, ty: extent.minY)).cropped(to: extent)
        guard !mask.strokes.isEmpty else { return base }

        // Unpainted pixels in the correction layer are transparent. Painted
        // pixels add coverage, erased pixels remove it, in the order drawn.
        guard let corrections = brush(mask, extent: extent, transparent: true) else { return nil }
        return corrections.composited(over: base).cropped(to: extent)
    }

    static func brushPreview(_ stroke: LocalMask.BrushStroke, extent: CGRect, region: CGRect) -> CIImage? {
        brush([stroke], feather: 0, extent: extent, transparent: true, region: region)
    }

    private static func brush(_ mask: LocalMask, extent: CGRect, transparent: Bool = false) -> CIImage? {
        brush(mask.strokes, feather: mask.feather, extent: extent, transparent: transparent)
    }

    private static func brush(_ strokes: [LocalMask.BrushStroke], feather maskFeather: Double,
                              extent: CGRect, transparent: Bool, region: CGRect? = nil) -> CIImage? {
        // Automatic corrections use a consistent grid so small brush strokes
        // match in the overlay, preview, and full-size export.
        let gridScale = 2048 / max(extent.width, extent.height)
        let scale = transparent ? gridScale : min(1, gridScale)
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        let grid = CGRect(x: 0, y: 0, width: width, height: height)
        let toGrid = CGAffineTransform(a: Double(width) / extent.width, b: 0, c: 0, d: Double(height) / extent.height,
                                       tx: -extent.minX * Double(width) / extent.width,
                                       ty: -extent.minY * Double(height) / extent.height)
        let patch = region.map { $0.applying(toGrid).integral.intersection(grid) } ?? grid
        guard !patch.isEmpty else { return nil }
        let space = transparent ? CGColorSpace(name: CGColorSpace.sRGB)! : CGColorSpaceCreateDeviceGray()
        let alphaInfo: CGImageAlphaInfo = transparent ? .premultipliedLast : .none
        guard let context = CGContext(data: nil, width: Int(patch.width), height: Int(patch.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: alphaInfo.rawValue) else { return nil }
        context.translateBy(x: -patch.minX, y: -patch.minY)
        if transparent { context.clear(patch) }
        else {
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(patch)
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * Double(width), y: p.y * Double(height)) }
            let radius = max(1, stroke.radius * Double(max(width, height)))
            let feather = min(max((stroke.softness ?? maskFeather) / 100, 0), 1)
            let strength = min(max((stroke.strength ?? 100) / 100, 0), 1)
            guard strength > 0 else { continue }
            let bands = feather > 0 ? (stroke.softness == nil ? 8 : 16) : 1
            let edge = stroke.edgeSelection
            let needsLayer = edge != nil || bands > 1
            if needsLayer { context.saveGState() }
            if let edge {
                guard let image = edge.image else { return nil }
                let b = edge.bounds
                let rect = CGRect(x: b.minX * Double(width), y: b.minY * Double(height),
                                  width: b.width * Double(width), height: b.height * Double(height))
                context.clip(to: rect, mask: image)
            }
            if needsLayer {
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                // Inner bands replace coverage within this stroke. Composite
                // the finished stroke once to avoid accumulating 8-bit rounding.
                context.setBlendMode(.copy)
            }
            let color: CGFloat = stroke.erases ? 0 : 1
            let tap = stroke.points.allSatisfy { $0 == first }
            for band in 0..<bands {
                let progress = Double(band) / Double(max(1, bands - 1))
                let inner = stroke.softness == nil ? 0.84 : 1
                let r = max(1, radius * (1 - progress * feather * inner))
                let fraction = Double(band + 1) / Double(bands)
                let ramp = stroke.softness == nil ? fraction : fraction * fraction * (3 - 2 * fraction)
                let alpha = strength * ramp
                context.setStrokeColor(gray: color, alpha: alpha)
                context.setFillColor(gray: color, alpha: alpha)
                context.setLineWidth(2 * r)
                let p = pixel(first)
                if tap {
                    context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                } else {
                    context.beginPath()
                    context.move(to: p)
                    for point in stroke.points.dropFirst() { context.addLine(to: pixel(point)) }
                    context.strokePath()
                }
            }
            if needsLayer {
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        guard let bitmap = context.makeImage() else { return nil }
        return CIImage(cgImage: bitmap, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(translationX: patch.minX, y: patch.minY))
            .transformed(by: toGrid.inverted())
    }
}
