import CoreImage

public enum PortraitControl: String, CaseIterable {
    case brighten = "LightImageSkinBrighten"
    case smooth = "LightImageSkinSmooth"
    case faceSlim = "LightImageFaceSlim"
    case waistSlim = "LightImageWaistSlim"
    case armSlim = "LightImageArmSlim"
    case legSlim = "LightImageLegSlim"

    public var key: String { rawValue }
}

enum PortraitEffects {
    // The mask follows the face ellipse and falls off at the boundary. Eyes,
    // eyebrows and lips are subtracted using landmark boxes.
    private static let retouchKernel = CIKernel(source: """
        float exclusion(vec2 p, vec4 region) {
            vec2 d = (p - region.xy) / max(region.zw, vec2(0.01));
            return smoothstep(0.65, 1.0, length(d));
        }
        float skinTone(vec3 rgb) {
            return smoothstep(-0.08, 0.036, rgb.r - rgb.b)
                 * smoothstep(-0.045, 0.020, rgb.r - rgb.g);
        }
        vec3 skinSample(sampler image, vec2 point) {
            return unpremultiply(sample(image, samplerTransform(image, point))).rgb;
        }
        kernel vec4 skin(sampler source, sampler soft, vec4 face, vec4 eyeA, vec4 eyeB, vec4 lips,
                        vec4 nose, float brighten, float smoothing, float blemishes, float spotRadius) {
            vec2 p = destCoord();
            vec4 color = unpremultiply(sample(source, samplerTransform(source, p)));
            vec3 blurred = skinSample(soft, p);
            float mask = 1.0 - smoothstep(0.67, 1.0, length((p - face.xy) / face.zw));
            mask *= exclusion(p, eyeA) * exclusion(p, eyeB) * exclusion(p, lips);
            vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
            float luma = dot(color.rgb, lumaWeights);
            float skinMask = mask * skinTone(color.rgb) * smoothstep(0.025, 0.16, luma);
            float edge = length(color.rgb - blurred);
            float blend = smoothing * 0.85 * skinMask * (1.0 - smoothstep(0.06, 0.24, edge));
            vec3 rgb = mix(color.rgb, blurred, blend);
            if (blemishes > 0.0 && mask > 0.0) {
                vec2 x = vec2(spotRadius, 0.0);
                vec2 y = vec2(0.0, spotRadius);
                vec2 d = (x + y) * 0.7071;
                vec2 e = (x - y) * 0.7071;
                vec3 left = skinSample(source, p - x), right = skinSample(source, p + x);
                vec3 lower = skinSample(source, p - y), upper = skinSample(source, p + y);
                vec3 diagA = skinSample(source, p - d), diagB = skinSample(source, p + d);
                vec3 diagC = skinSample(source, p - e), diagD = skinSample(source, p + e);
                vec3 surrounding = (left + right + lower + upper + diagA + diagB + diagC + diagD) / 8.0;
                float variation = max(max(length(left - right), length(lower - upper)),
                                      max(length(diagA - diagB), length(diagC - diagD)));
                vec3 delta = color.rgb - surrounding;
                float contrast = max(abs(dot(delta, lumaWeights)), (delta.r - delta.g) * 0.85);
                float spot = smoothstep(0.035, 0.12, contrast) * (1.0 - smoothstep(0.045, 0.16, variation));
                float repair = blemishes * mask * spot * exclusion(p, nose) * skinTone(surrounding);
                repair *= smoothstep(0.025, 0.16, dot(surrounding, lumaWeights));
                rgb = mix(rgb, surrounding, repair);
            }
            float lift = 0.50 * brighten * skinMask * luma * (1.0 - luma);
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
        let extent = source.extent
        func bodyAmount(_ control: PortraitControl) -> Double {
            amount(adjustments[control.key])
        }
        var image = source
        let faces = zip(analysis.subjects, adjustments.faceRetouch.settings(for: analysis.subjects))
        for (subject, settings) in faces where settings.brighten > 0 || settings.smoothing > 0 || settings.blemishes > 0 {
            image = try retouch(image, subject: subject, settings: settings)
        }
        for (subject, settings) in faces where settings.slim > 0 {
            let face = pixels(subject.face, in: extent)
            let center = CGPoint(x: face.midX, y: face.minY + face.height * 0.43)
            var angle = 0.0
            if subject.eyes.count == 2 {
                let eyes = subject.eyes.map { pixels($0, in: extent) }.sorted { $0.midX < $1.midX }
                angle = atan2(eyes[1].midY - eyes[0].midY, eyes[1].midX - eyes[0].midX)
            }
            image = try slim(image, center: center, radiusX: face.width * 0.78,
                             radiusY: face.height * 0.58, angle: angle, strength: amount(settings.slim) * 0.44, jaw: true)
        }

        let subjects = analysis.targets(adjustments.portraitFace)
        let slimWaist = bodyAmount(.waistSlim)
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
        let slimArms = bodyAmount(.armSlim), slimLegs = bodyAmount(.legSlim)
        for subject in subjects {
            let faceWidth = subject.face.width * extent.width
            if slimArms > 0 {
                image = try slimLimbs(image, subject.arms, radius: faceWidth * 0.55, strength: slimArms)
            }
            if slimLegs > 0 {
                image = try slimLimbs(image, subject.legs, radius: faceWidth * 0.75, strength: slimLegs)
            }
        }
        return image
    }

    private static func amount(_ value: Double) -> Double { min(max(value / 100, 0), 1) }

    private static func retouch(_ image: CIImage, subject: PortraitSubject, settings: PortraitRetouch.Settings) throws -> CIImage {
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
        let soft = settings.smoothing > 0 ? image.clampedToExtent().applyingFilter("CIGaussianBlur",
                        parameters: [kCIInputRadiusKey: max(0.5, face.width * 0.028)]) : image
        let spotRadius = max(1.5, face.width * 0.022)
        let args: [Any] = [image.clampedToExtent(), soft, ellipse(region), protection(subject.eyes.first),
                           protection(subject.eyes.dropFirst().first), protection(subject.lips), protection(subject.nose),
                           amount(settings.brighten), amount(settings.smoothing), amount(settings.blemishes), spotRadius]
        guard let output = retouchKernel?.apply(extent: patch, roiCallback: { index, rect in
            index == 0 ? rect.insetBy(dx: -ceil(spotRadius) - 1, dy: -ceil(spotRadius) - 1) : rect
        }, arguments: args) else {
            throw LightImageError.portraitFailed
        }
        return replace(image, with: output)
    }

    private static func slimLimbs(_ source: CIImage, _ limbs: [PortraitLimb], radius: Double,
                                  strength: Double) throws -> CIImage {
        let extent = source.extent
        var image = source
        for limb in limbs {
            let dx = (limb.end.x - limb.start.x) * extent.width
            let dy = (limb.end.y - limb.start.y) * extent.height
            let length = hypot(dx, dy)
            let center = CGPoint(x: extent.minX + (limb.start.x + limb.end.x) / 2 * extent.width,
                                 y: extent.minY + (limb.start.y + limb.end.y) / 2 * extent.height)
            image = try slim(image, center: center, radiusX: min(radius, length * 0.5), radiusY: length * 0.49,
                             angle: atan2(-dx, dy), strength: strength * 0.62, jaw: false)
        }
        return image
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
