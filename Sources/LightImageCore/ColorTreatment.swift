import Foundation
import simd

/// Independent approximations in display-referred sRGB, not Adobe's DCP/Camera Raw engine.
struct ColorTreatment {
    let a: Adjustments
    let calibration: simd_double3x3
    let hasCalibration: Bool
    let parametric: [Double]
    let splits: [Double]
    let hues: [Double], saturations: [Double], luminances: [Double], gray: [Double]
    let hasHSL: Bool
    let gradingColors: [SIMD3<Double>]
    let gradingLum: [Double]
    let hasGrading: Bool
    let blending: Double, balance: Double
    let curves: [[Double]]
    static let externalKeys: Set<String> = ["AutoTone", "Dehaze", "Exposure2012", "Temperature", "Tint", "IncrementalTemperature", "IncrementalTint", "Vibrance", "Clarity2012", "Texture", "Sharpness", "SharpenRadius", "SharpenDetail", "SharpenEdgeMasking", "LuminanceSmoothing", "LuminanceNoiseReductionDetail", "LuminanceNoiseReductionContrast", "ColorNoiseReduction", "ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness", "PerspectiveScale", "PerspectiveX", "PerspectiveY", "PostCropVignetteAmount", "VignetteAmount"]
    static func settings(from a: Adjustments) -> Adjustments {
        var result = Adjustments(); result.curves = a.curves; result.monochrome = a.monochrome
        result.trongTreo3Calibration = a.trongTreo3Calibration
        result.values = a.values.filter {
            !externalKeys.contains($0.key) && !FilmEffects.keys.contains($0.key) &&
                $0.key != "LightImageStraighten" && PortraitControl(rawValue: $0.key) == nil &&
                !PresetParameters.isNeutral($0.key, value: $0.value, in: a)
        }
        return result
    }
    static let dimension = 64
    static let centers = [0.0, 30, 60, 120, 180, 240, 270, 300]

    init(_ settings: Adjustments) {
        a = settings
        let primaryNames = ["Red", "Green", "Blue"]
        hasCalibration = primaryNames.contains { settings[$0 + "Hue"] != 0 || settings[$0 + "Saturation"] != 0 }
        // Independent primary-calibration approximation, not an Adobe DCP.
        // Move primary chromaticities around D65 and solve the inverse mapping
        // with a shared white point. The slider scale is empirical; it was checked
        // against one JPEG/Lightroom reference pair, not a universal calibration.
        let white = SIMD2<Double>(0.3127, 0.3290)
        let xy = [SIMD2<Double>(0.64, 0.33), SIMD2<Double>(0.30, 0.60), SIMD2<Double>(0.15, 0.06)]
        func primaryMatrix(_ coordinates: [SIMD2<Double>]) -> simd_double3x3 {
            let columns = coordinates.map { p in SIMD3(p.x / p.y, 1, (1 - p.x - p.y) / p.y) }
            let m = simd_double3x3(columns: (columns[0], columns[1], columns[2]))
            let gains = m.inverse * SIMD3(white.x / white.y, 1, (1 - white.x - white.y) / white.y)
            return simd_double3x3(columns: (columns[0] * gains.x, columns[1] * gains.y, columns[2] * gains.z))
        }
        var adjusted = xy
        for (index, name) in primaryNames.enumerated() {
            let angle = settings[name + "Hue"] * -0.15 * .pi / 180
            let v = (xy[index] - white) * (1 - settings[name + "Saturation"] / 100 * 0.50)
            let p = white + SIMD2(cos(angle) * v.x - sin(angle) * v.y, sin(angle) * v.x + cos(angle) * v.y)
            adjusted[index] = SIMD2(max(0.01, p.x), max(0.01, p.y))
        }
        calibration = primaryMatrix(adjusted).inverse * primaryMatrix(xy)
        parametric = ["Shadows", "Darks", "Lights", "Highlights"].map { settings["Parametric" + $0] / 100 }
        // Constrain crossed dividers safely, while retaining their named order.
        let low = min(max(settings["ParametricShadowSplit"] / 100, 0.01), 0.97)
        let mid = min(max(settings["ParametricMidtoneSplit"] / 100, low + 0.01), 0.98)
        splits = [low, mid, min(max(settings["ParametricHighlightSplit"] / 100, mid + 0.01), 0.99)]
        hues = PresetParser.colorNames.map { settings["HueAdjustment" + $0] }
        saturations = PresetParser.colorNames.map { settings["SaturationAdjustment" + $0] }
        luminances = PresetParser.colorNames.map { settings["LuminanceAdjustment" + $0] }
        gray = PresetParser.colorNames.map { settings["GrayMixer" + $0] }
        hasHSL = (hues + saturations + luminances + gray).contains { $0 != 0 }
        let gradingHues = [settings["SplitToningShadowHue"], settings["ColorGradeMidtoneHue"], settings["SplitToningHighlightHue"], settings["ColorGradeGlobalHue"]]
        let gradingSat = [settings["SplitToningShadowSaturation"], settings["ColorGradeMidtoneSat"], settings["SplitToningHighlightSaturation"], settings["ColorGradeGlobalSat"]]
        gradingColors = zip(gradingHues, gradingSat).map { (Self.hslToRGB($0.0, 1, 0.5) - SIMD3(repeating: 0.5)) * ($0.1 / 100 * 0.70) }
        gradingLum = ["Shadow", "Midtone", "Highlight", "Global"].map { settings["ColorGrade" + $0 + "Lum"] / 100 }
        hasGrading = gradingSat.contains { $0 > 0 } || gradingLum.contains { $0 != 0 }
        blending = settings["ColorGradeBlending"] / 100; balance = settings["SplitToningBalance"] / 100
        curves = ["ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue"].map { key in
            (0...4096).map { ImageEngine.curve(Double($0) / 4096, settings.curves[key]) }
        }
    }
    func makeCube() -> Data {
        let dimension = Self.dimension
        var data = [Float](); data.reserveCapacity(dimension * dimension * dimension * 4)
        for b in 0..<dimension { for g in 0..<dimension { for r in 0..<dimension {
            let rgb = transform(SIMD3(Double(r), Double(g), Double(b)) / Double(dimension - 1))
            data.append(contentsOf: [Float(rgb.x), Float(rgb.y), Float(rgb.z), 1])
        } } }
        return data.withUnsafeBytes { Data($0) }
    }
    func curve(_ v: Double, _ index: Int) -> Double {
        let f = Self.clamp(v) * 4096, lo = Int(f), hi = min(lo + 1, 4096)
        return curves[index][lo] + (curves[index][hi] - curves[index][lo]) * (f - Double(lo))
    }
    /// Tonal sliders operate on luminance; applying Highlights/Whites separately
    /// to RGB channels desaturates skin and lifts colored shadows into a grey veil.
    func basicTone(_ value: Double) -> Double {
        let t = Self.clamp(value)
        let contrast = a["Contrast2012"] / 100
        let contrasted = Self.clamp(t + contrast * (t - 0.5) * 4 * t * (1 - t) * 0.5)
        let shadows = a["Shadows2012"] / 100 * 0.85 * t * pow(1 - t, 3)
        let highlights = a["Highlights2012"] / 100 * 0.45 * t * t * (1 - t)
        let whiteAmount = a["Whites2012"] / 100
        // A rational shoulder keeps near-white tones ordered even at Whites = -100.
        let whites = whiteAmount < 0
            ? t / (1 - 0.47 * whiteAmount * t * t * t) - t
            : whiteAmount * 0.38 * pow(t, 4)
        let blacks = a["Blacks2012"] / 100 * 0.7 * t * pow(1 - t, 4)
        return Self.clamp(contrasted + shadows + highlights + whites + blacks)
    }
    func tone(_ value: Double) -> Double {
        let v = Self.clamp(value)
        let s = Self.smooth(splits[0] - 0.15, splits[0] + 0.15, v)
        let m = Self.smooth(splits[1] - 0.15, splits[1] + 0.15, v)
        let h = Self.smooth(splits[2] - 0.15, splits[2] + 0.15, v)
        let amount = parametric[0] * (1 - s) + parametric[1] * s * (1 - m) + parametric[2] * m * (1 - h) + parametric[3] * h
        return curve(Self.clamp(v + amount * 0.24 * 4 * v * (1 - v)), 0)
    }
    func transform(_ input: SIMD3<Double>) -> SIMD3<Double> {
        var rgb = input
        if hasCalibration {
            let linear = SIMD3(Self.linear(rgb.x), Self.linear(rgb.y), Self.linear(rgb.z))
            let calibrated = calibration * linear
            rgb = SIMD3(Self.gamma(calibrated.x), Self.gamma(calibrated.y), Self.gamma(calibrated.z))
        }
        if a["ShadowTint"] != 0 {
            let tint = a["ShadowTint"] / 100 * pow(1 - Self.clamp(Self.luma(rgb)), 2) * 0.08
            rgb += SIMD3(tint * 0.5, -tint, tint * 0.5)
        }
        let luminance = Self.luma(rgb)
        if luminance > 1e-8 { rgb *= basicTone(luminance) / luminance }
        // Blend the composite RGB curve with a luminance-preserving-hue application.
        // Use the curve's black point as an offset so lifted blacks stay neutral.
        let channelTone = SIMD3(tone(rgb.x), tone(rgb.y), tone(rgb.z))
        let yBeforeCurve = Self.luma(rgb)
        let floor = curves[0][0]
        if yBeforeCurve > 1e-8 {
            let luminanceTone = SIMD3(repeating: floor) + rgb * ((tone(yBeforeCurve) - floor) / yBeforeCurve)
            rgb = simd_clamp(channelTone * 0.4 + luminanceTone * 0.6, .zero, SIMD3(repeating: 1))
        } else {
            rgb = channelTone
        }
        var grayDelta = 0.0
        if hasHSL {
            var hsl = Self.rgbToHSL(rgb)
            var dh = 0.0, ds = 0.0, dl = 0.0, total = 0.0
            for c in 0..<8 {
                let distance = min(abs(hsl.x - Self.centers[c]), 360 - abs(hsl.x - Self.centers[c]))
                let weight = max(0, 1 - distance / 60)
                dh += weight * hues[c]; ds += weight * saturations[c]; dl += weight * luminances[c]; grayDelta += weight * gray[c]; total += weight
            }
            if total > 0 { dh /= total; ds /= total; dl /= total; grayDelta /= total }
            hsl.x += dh * 0.3
            let chromaWeight = Self.smooth(0, 0.25, hsl.y)
            hsl.y = Self.clamp(hsl.y * (1 + ds / 100))
            rgb = Self.hslToRGB(hsl.x, hsl.y, hsl.z)
            var gain = pow(2, dl / 100 * chromaWeight * 0.4)
            // Preserve hue and reserve highlight headroom instead of adding white
            // to the HSL lightness channel or clipping bright foliage to yellow.
            if gain > 1 { gain = 1 + (gain - 1) * (1 - Self.clamp(max(rgb.x, rgb.y, rgb.z))) }
            rgb *= gain
        }
        let y = Self.luma(rgb)
        if a.monochrome { rgb = SIMD3(repeating: Self.clamp(y + grayDelta / 100 * 0.25)) }
        else { rgb = SIMD3(repeating: y) + (rgb - SIMD3(repeating: y)) * (1 + a["Saturation"] / 100) }
        rgb = SIMD3(curve(rgb.x, 1), curve(rgb.y, 2), curve(rgb.z, 3))
        if hasGrading { rgb = grade(rgb) }
        rgb = simd_clamp(rgb, .zero, SIMD3(repeating: 1))
        if !a.monochrome, let strength = a.trongTreo3Calibration, strength > 0 {
            return TrongTreo3Calibration.apply(to: rgb, strength: min(1, strength))
        }
        return rgb
    }
    func grade(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let t = Self.clamp(Self.luma(rgb) + balance * 0.35)
        let shadow = (1 - Self.smooth(0.08, 0.42, t)) * (1 - blending) + (1 - t) * blending
        let highlight = Self.smooth(0.58, 0.92, t) * (1 - blending) + t * blending
        let mid = (Self.smooth(0.08, 0.42, t) * (1 - Self.smooth(0.58, 0.92, t))) * (1 - blending) + 4 * t * (1 - t) * blending
        let delta = gradingLum[0] * shadow + gradingLum[1] * mid + gradingLum[2] * highlight + gradingLum[3]
        var result = rgb + SIMD3(repeating: delta * 0.25)
        result = SIMD3(Self.clamp(result.x), Self.clamp(result.y), Self.clamp(result.z))
        let tint = gradingColors[0] * shadow + gradingColors[1] * mid + gradingColors[2] * highlight
        for c in 0..<3 {
            result[c] = Self.softLight(result[c], Self.clamp(0.5 + tint[c]))
            result[c] = Self.softLight(result[c], Self.clamp(0.5 + gradingColors[3][c]))
        }
        return result
    }
    static func softLight(_ x: Double, _ blend: Double) -> Double {
        if blend <= 0.5 { return x - (1 - 2 * blend) * x * (1 - x) }
        let d = x <= 0.25 ? ((16 * x - 12) * x + 4) * x : sqrt(x)
        return x + (2 * blend - 1) * (d - x)
    }
    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func smooth(_ low: Double, _ high: Double, _ x: Double) -> Double { let t = clamp((x - low) / max(1e-6, high - low)); return t * t * (3 - 2 * t) }
    static func luma(_ x: SIMD3<Double>) -> Double { simd_dot(x, SIMD3(0.2126, 0.7152, 0.0722)) }
    static func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    static func gamma(_ x: Double) -> Double { x <= 0.0031308 ? 12.92 * max(0, x) : 1.055 * pow(x, 1 / 2.4) - 0.055 }
    static func rgbToHSL(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let hi = max(rgb.x, rgb.y, rgb.z), lo = min(rgb.x, rgb.y, rgb.z), d = hi - lo, l = (hi + lo) / 2
        guard d > 1e-8 else { return SIMD3(0, 0, l) }
        let s = d / max(1e-8, 1 - abs(2 * l - 1))
        let h = hi == rgb.x ? ((rgb.y - rgb.z) / d).truncatingRemainder(dividingBy: 6) : hi == rgb.y ? (rgb.z - rgb.x) / d + 2 : (rgb.x - rgb.y) / d + 4
        return SIMD3((h * 60 + 360).truncatingRemainder(dividingBy: 360), s, l)
    }
    static func hslToRGB(_ hue: Double, _ s: Double, _ l: Double) -> SIMD3<Double> {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let rgb: SIMD3<Double>
        switch h { case ..<60: rgb = SIMD3(c, x, 0); case ..<120: rgb = SIMD3(x, c, 0); case ..<180: rgb = SIMD3(0, c, x); case ..<240: rgb = SIMD3(0, x, c); case ..<300: rgb = SIMD3(x, 0, c); default: rgb = SIMD3(c, 0, x) }
        return rgb + SIMD3(repeating: m)
    }
}
