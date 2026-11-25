import CoreImage

public enum PortraitControl: String, CaseIterable {
    case brighten = "LightImageSkinBrighten"
    case smooth = "LightImageSkinSmooth"
    case faceSlim = "LightImageFaceSlim"
    case waistSlim = "LightImageWaistSlim"

    public var key: String { rawValue }
}

enum PortraitEffects {
    // The mask follows the face ellipse and falls off at the boundary. Eyes,
    // eyebrows and lips are subtracted using landmark boxes.
    private static let retouchKernel = CIColorKernel(source: """
        float exclusion(vec2 p, vec4 region) {
            vec2 d = (p - region.xy) / max(region.zw, vec2(0.01));
            return smoothstep(0.65, 1.0, length(d));
        }
        kernel vec4 skin(__sample source, __sample soft, vec4 face,
                        vec4 eyeA, vec4 eyeB, vec4 lips, float brighten, float smoothing) {
            vec2 p = destCoord();
            vec4 color = unpremultiply(source);
            vec3 blurred = unpremultiply(soft).rgb;
            float mask = 1.0 - smoothstep(0.67, 1.0, length((p - face.xy) / face.zw));
            mask *= exclusion(p, eyeA) * exclusion(p, eyeB) * exclusion(p, lips);
            float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
            float skinTone = smoothstep(-0.08, 0.036, color.r - color.b)
                           * smoothstep(-0.045, 0.020, color.r - color.g);
            mask *= skinTone * smoothstep(0.025, 0.16, luma);
            float edge = length(color.rgb - blurred);
            float blend = smoothing * mask * (1.0 - smoothstep(0.06, 0.24, edge));
            vec3 rgb = mix(color.rgb, blurred, blend);
            float lift = 0.50 * brighten * mask * luma * (1.0 - luma);
            rgb += (vec3(1.0) - rgb) * (lift / max(0.12, 1.0 - luma));
            return premultiply(vec4(rgb, color.a));
        }
        """)

    // Inverse horizontal displacement in the subject's local coordinates.
    // Compact support and a smooth falloff avoid a seam at the edge.
    private static let slimKernel = CIWarpKernel(source: """
        kernel vec2 slim(vec4 region, vec2 axis, float strength, float jaw) {
            vec2 p = destCoord();
            vec2 up = vec2(-axis.y, axis.x);
            vec2 delta = p - region.xy;
            vec2 local = vec2(dot(delta, axis), dot(delta, up)) / region.zw;
            float r2 = dot(local, local);
            float w = max(0.0, 1.0 - r2);
            float lower = mix(1.0, 1.0 - smoothstep(-0.20, 0.80, local.y), jaw);
            return p + axis * (local.x * region.z * strength * w * w * lower);
        }
        """)

    static func apply(_ source: CIImage, adjustments: Adjustments, analysis: PortraitAnalysis) throws -> CIImage {
        let subjects = analysis.targets(adjustments.portraitFace)
        let extent = source.extent
        func amount(_ control: PortraitControl) -> Double {
            min(max(adjustments[control.key] / 100, 0), 1)
        }
        var image = source
        let brighten = amount(.brighten), smoothing = amount(.smooth)
        if brighten > 0 || smoothing > 0 {
            for subject in subjects {
                image = try retouch(image, subject: subject, brighten: brighten, smoothing: smoothing)
            }
        }
        let slimFace = amount(.faceSlim)
        if slimFace > 0 {
            for subject in subjects {
                let face = pixels(subject.face, in: extent)
                let center = CGPoint(x: face.midX, y: face.minY + face.height * 0.43)
                var angle = 0.0
                if subject.eyes.count == 2 {
                    let eyes = subject.eyes.map { pixels($0, in: extent) }.sorted { $0.midX < $1.midX }
                    angle = atan2(eyes[1].midY - eyes[0].midY, eyes[1].midX - eyes[0].midX)
                }
                image = try slim(image, center: center, radiusX: face.width * 0.78,
                                 radiusY: face.height * 0.58, angle: angle, strength: slimFace * 0.44, jaw: true)
            }
        }

        let slimWaist = amount(.waistSlim)
        if slimWaist > 0 {
            let waists = adjustments.portraitWaist.map { [$0] } ?? subjects.compactMap(\.waist)
            for waist in waists {
                let center = CGPoint(x: extent.minX + waist.center.x * extent.width,
                                     y: extent.minY + waist.center.y * extent.height)
                let width = min(max(waist.width, 0.02), 0.8) * extent.width
                image = try slim(image, center: center, radiusX: width * 0.72, radiusY: width * 0.43,
                                 angle: waist.angle, strength: slimWaist * 0.62, jaw: false)
            }
        }
        return image
    }

    private static func retouch(_ image: CIImage, subject: PortraitSubject, brighten: Double,
                                smoothing: Double) throws -> CIImage {
        let face = pixels(subject.face, in: image.extent)
        let region = CGRect(x: face.minX + face.width * 0.035, y: face.minY + face.height * 0.04,
                            width: face.width * 0.93, height: face.height * 0.91)
        let patch = region.integral.intersection(image.extent)
        guard !patch.isEmpty else { return image }
        func protection(_ rect: CGRect?) -> CIVector {
            guard let rect else { return CIVector(x: -1e6, y: -1e6, z: 1, w: 1) }
            let bounds = pixels(rect, in: image.extent).insetBy(dx: -face.width * 0.05, dy: -face.height * 0.044)
            return ellipse(bounds)
        }
        let soft = smoothing > 0 ? image.clampedToExtent().applyingFilter("CIGaussianBlur",
                        parameters: [kCIInputRadiusKey: max(0.5, face.width * 0.028)]) : image
        let args: [Any] = [image, soft, ellipse(region), protection(subject.eyes.first),
                           protection(subject.eyes.dropFirst().first), protection(subject.lips), brighten, smoothing * 0.85]
        guard let output = retouchKernel?.apply(extent: patch, arguments: args) else {
            throw LightImageError.portraitFailed
        }
        return replace(image, with: output)
    }

    private static func slim(_ image: CIImage, center: CGPoint, radiusX: Double, radiusY: Double,
                             angle: Double, strength: Double, jaw: Bool) throws -> CIImage {
        guard radiusX >= 2, radiusY >= 2 else { return image }
        let ax = cos(angle), ay = sin(angle)
        let dx = hypot(radiusX * ax, radiusY * ay)
        let dy = hypot(radiusX * ay, radiusY * ax)
        let patch = CGRect(x: center.x - dx, y: center.y - dy, width: 2 * dx, height: 2 * dy)
            .integral.intersection(image.extent)
        guard !patch.isEmpty else { return image }
        let margin = ceil(radiusX * strength) + 2
        let args: [Any] = [CIVector(x: center.x, y: center.y, z: radiusX, w: radiusY),
                           CIVector(x: ax, y: ay), strength, jaw ? 1.0 : 0.0]
        guard let output = slimKernel?.apply(extent: patch, roiCallback: { _, rect in
            rect.insetBy(dx: -margin, dy: -margin)
        }, image: image.clampedToExtent(), arguments: args) else { throw LightImageError.portraitFailed }
        return replace(image, with: output)
    }

    private static func replace(_ original: CIImage, with patch: CIImage) -> CIImage {
        // A rectangle mask replaces the patch even when a PNG has alpha.
        let mask = CIImage(color: .white).cropped(to: patch.extent)
        return patch.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: original, kCIInputMaskImageKey: mask
        ]).cropped(to: original.extent)
    }

    private static func pixels(_ rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(x: extent.minX + rect.minX * extent.width, y: extent.minY + rect.minY * extent.height,
               width: rect.width * extent.width, height: rect.height * extent.height)
    }

    private static func ellipse(_ rect: CGRect) -> CIVector {
        CIVector(x: rect.midX, y: rect.midY, z: rect.width / 2, w: rect.height / 2)
    }
}
