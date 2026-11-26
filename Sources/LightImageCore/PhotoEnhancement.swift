import CoreImage

public enum PhotoEnhancement: String {
    case detail = "LightImageDetail"
    case restore = "LightImageRestorePhoto"
    case lensBlur = "LightImageLensBlur"

    public var key: String { rawValue }

    static func restore(_ source: CIImage, amount: Double, engine: ImageEngine) throws -> CIImage {
        guard amount > 0 else { return source }
        let extent = source.extent
        let cleaned = source.clampedToExtent().applyingFilter("CIMedianFilter").cropped(to: extent)
        let restored = try AdvancedEffects.automaticTone(cleaned, engine: engine)
        let weight = min(amount / 100, 1)
        let mask = CIImage(color: CIColor(red: weight, green: weight, blue: weight)).cropped(to: extent)
        return restored.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: source, kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }

    static func enhanceDetail(_ image: CIImage, amount: Double) -> CIImage {
        guard amount > 0 else { return image }
        let strength = min(amount / 100, 1)
        let scale = max(image.extent.width, image.extent.height) / 2400
        // A smaller radius brings out detail. The noise controls run earlier in the pipeline.
        return image.clampedToExtent().applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: strength * 0.75, kCIInputRadiusKey: max(0.5, scale * 1.7)
        ]).cropped(to: image.extent)
    }

    static func blurBackground(_ source: CIImage, foreground data: Data?, amount: Double) throws -> CIImage {
        guard amount > 0, let data else { return source }
        let extent = source.extent
        var mask = LocalMask(kind: .subject)
        mask.automaticPNG = data
        mask.feather = 30
        let radius = max(extent.width, extent.height) * 0.018 * min(amount / 100, 1)
        guard let foreground = LocalMaskRenderer.automaticCoverage(mask, extent: extent) else {
            throw LightImageError.exportFailed("Không đọc được vùng chủ thể để xóa phông.")
        }
        let background = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            kCIInputMaskImageKey: foreground.applyingFilter("CIColorInvert")
        ]).cropped(to: extent)
        let blurred = background.clampedToExtent().applyingFilter("CIDiscBlur", parameters: [
            kCIInputRadiusKey: radius
        ]).cropped(to: extent)
        guard let result = compositeBlur?.apply(extent: extent, arguments: [source, blurred, foreground]) else {
            throw LightImageError.exportFailed("Không thể kết xuất hiệu ứng xóa phông.")
        }
        return result
    }

    // Blur only the background samples so the foreground color doesn't bleed around the subject.
    private static let compositeBlur = CIColorKernel(source: """
        kernel vec4 blurBackground(__sample source, __sample blurred, __sample foreground) {
            float coverage = (1.0 - foreground.r) * smoothstep(0.015, 0.16, blurred.a);
            vec3 background = blurred.rgb / max(blurred.a, 0.015);
            return mix(source, vec4(background * source.a, source.a), coverage);
        }
        """)
}
