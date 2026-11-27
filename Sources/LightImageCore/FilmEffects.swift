import CoreImage

enum FilmEffects {
    private static let grain = CIColorKernel(source: """
        float hash(vec2 p) {
            vec3 q = fract(vec3(p.xyx) * 0.1031);
            q += dot(q, q.yzx + 33.33);
            return fract((q.x + q.y) * q.z);
        }
        kernel vec4 filmGrain(__sample image, float cell, float intensity, float roughness) {
            vec2 p = destCoord() / cell;
            float fine = hash(floor(p)) - 0.5;
            vec2 f = fract(p);
            vec2 base = floor(p);
            vec2 t = f * f * (3.0 - 2.0 * f);
            float soft = mix(mix(hash(base), hash(base + vec2(1.0, 0.0)), t.x),
                               mix(hash(base + vec2(0.0, 1.0)), hash(base + vec2(1.0, 1.0)), t.x), t.y) - 0.5;
            vec4 color = unpremultiply(image);
            float y = clamp(dot(color.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
            float delta = mix(soft, fine, roughness) * intensity * sqrt(4.0 * y * (1.0 - y));
            return premultiply(vec4(clamp(color.rgb + delta, 0.0, 1.0), color.a));
        }
        """)

    private static let vignette = CIColorKernel(source: """
        kernel vec4 filmVignette(__sample image, vec4 frame, float strength,
                                float midpoint, float feather, float roundness, float highlights) {
            vec2 d = abs((destCoord() - frame.xy) / frame.zw);
            float power = mix(5.0, 1.6, roundness);
            float radius = pow(pow(d.x, power) + pow(d.y, power), 1.0 / power);
            float falloff = smoothstep(midpoint, midpoint + feather, radius);
            vec4 color = unpremultiply(image);
            float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
            float gain = strength * falloff;
            if (gain < 0.0) gain *= 1.0 - highlights * smoothstep(0.4, 0.96, luma);
            vec3 rgb = color.rgb + gain * (gain < 0.0 ? color.rgb : 1.0 - color.rgb);
            return premultiply(vec4(rgb, color.a));
        }
        """)

    static let vignetteKeys = ["PostCropVignetteMidpoint", "PostCropVignetteFeather", "PostCropVignetteRoundness", "PostCropVignetteHighlightContrast"]
    static let keys = Set(vignetteKeys + ["GrainAmount", "GrainSize", "GrainFrequency"])

    static func apply(_ image: CIImage, adjustments a: Adjustments) throws -> CIImage {
        let extent = image.extent
        var result = image
        if a["GrainAmount"] > 0 {
            let cell = max(0.45, max(extent.width, extent.height) / 2400 * (0.75 + a["GrainSize"] / 28))
            guard let output = grain?.apply(extent: extent, arguments: [
                result, cell, a["GrainAmount"] / 100 * 0.31, a["GrainFrequency"] / 100
            ]) else { throw LightImageError.exportFailed(tr("Không thể tạo hạt film.")) }
            result = output
        }
        let amount = a.values["PostCropVignetteAmount"] ?? a["VignetteAmount"]
        guard amount != 0 else { return result }
        if !vignetteKeys.contains(where: { a.values[$0] != nil }) {
            // Preserve the appearance of existing presets and catalog entries.
            return result.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: -amount / 55, kCIInputRadiusKey: max(extent.width, extent.height) * 0.45
            ])
        }
        let frame = CIVector(x: extent.midX, y: extent.midY, z: extent.width / 2, w: extent.height / 2)
        guard let output = vignette?.apply(extent: extent, arguments: [
            result, frame, amount / 100 * 0.90, 0.08 + a["PostCropVignetteMidpoint"] * 0.009,
            0.04 + a["PostCropVignetteFeather"] * 0.009, (a["PostCropVignetteRoundness"] + 100) / 200,
            a["PostCropVignetteHighlightContrast"] / 100
        ]) else { throw LightImageError.exportFailed(tr("Không thể kết xuất hiệu ứng tối góc.")) }
        return output
    }
}
