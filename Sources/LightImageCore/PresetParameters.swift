import Foundation

/// Adobe control semantics; processing remains an independent approximation.
public enum PresetParameters {
    public static let defaults: [String: Double] = [
        "SharpenRadius": 1, "SharpenDetail": 25, "LuminanceNoiseReductionDetail": 50,
        "ColorNoiseReductionDetail": 50, "ColorNoiseReductionSmoothness": 50,
        "ParametricShadowSplit": 25, "ParametricMidtoneSplit": 50, "ParametricHighlightSplit": 75,
        "ColorGradeBlending": 50, "PerspectiveScale": 100,
        "GrainSize": 25, "GrainFrequency": 50, "PostCropVignetteMidpoint": 50,
        "PostCropVignetteFeather": 50,
        "DefringePurpleHueLo": 30, "DefringePurpleHueHi": 70,
        "DefringeGreenHueLo": 40, "DefringeGreenHueHi": 60
    ]
    public static let circular: Set<String> = ["SplitToningShadowHue", "SplitToningHighlightHue", "ColorGradeMidtoneHue", "ColorGradeGlobalHue"]
    public static let additionalRanges: [String: ClosedRange<Double>] = {
        var r: [String: ClosedRange<Double>] = [
            "AutoTone": 0...1, "Dehaze": -100...100, "ShadowTint": -100...100,
            "SplitToningBalance": -100...100, "ColorGradeBlending": 0...100,
            "SharpenRadius": 0.5...3, "SharpenDetail": 0...100, "SharpenEdgeMasking": 0...100,
            "ColorNoiseReduction": 0...100, "ColorNoiseReductionDetail": 0...100, "ColorNoiseReductionSmoothness": 0...100,
            "LuminanceNoiseReductionDetail": 0...100, "LuminanceNoiseReductionContrast": 0...100,
            "PerspectiveScale": 50...150, "PerspectiveX": -100...100, "PerspectiveY": -100...100,
            "GrainAmount": 0...100, "GrainSize": 0...100, "GrainFrequency": 0...100,
            "PostCropVignetteMidpoint": 0...100, "PostCropVignetteFeather": 0...100,
            "PostCropVignetteRoundness": -100...100, "PostCropVignetteHighlightContrast": 0...100
        ]
        for color in ["Red", "Green", "Blue"] { r[color + "Hue"] = -100...100; r[color + "Saturation"] = -100...100 }
        for zone in ["Shadows", "Darks", "Lights", "Highlights"] { r["Parametric" + zone] = -100...100 }
        for split in ["Shadow", "Midtone", "Highlight"] { r["Parametric" + split + "Split"] = 0...100 }
        for zone in ["Shadow", "Highlight"] { r["SplitToning" + zone + "Hue"] = 0...360; r["SplitToning" + zone + "Saturation"] = 0...100 }
        for zone in ["Midtone", "Global"] { r["ColorGrade" + zone + "Hue"] = 0...360; r["ColorGrade" + zone + "Sat"] = 0...100 }
        for zone in ["Shadow", "Midtone", "Highlight", "Global"] { r["ColorGrade" + zone + "Lum"] = -100...100 }
        return r
    }()
    public static func isActive(_ key: String, in a: Adjustments) -> Bool {
        switch key {
        case PhotoEnhancement.lensBlur.key: return a.lensBlurSubject != nil
        case "GrainSize", "GrainFrequency": return a["GrainAmount"] > 0
        case "PostCropVignetteMidpoint", "PostCropVignetteFeather", "PostCropVignetteRoundness", "PostCropVignetteHighlightContrast":
            return (a.values["PostCropVignetteAmount"] ?? a["VignetteAmount"]) != 0
        case "SharpenRadius", "SharpenDetail", "SharpenEdgeMasking": return a["Sharpness"] > 0
        case "ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness": return a["ColorNoiseReduction"] > 0
        case "LuminanceNoiseReductionDetail", "LuminanceNoiseReductionContrast": return a["LuminanceSmoothing"] > 0
        case "DefringePurpleHueLo", "DefringePurpleHueHi": return a["DefringePurpleAmount"] > 0
        case "DefringeGreenHueLo", "DefringeGreenHueHi": return a["DefringeGreenAmount"] > 0
        case "ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit":
            return ["Shadows", "Darks", "Lights", "Highlights"].contains { a["Parametric" + $0] != 0 }
        case "SplitToningShadowHue": return a["SplitToningShadowSaturation"] > 0
        case "SplitToningHighlightHue": return a["SplitToningHighlightSaturation"] > 0
        case "ColorGradeMidtoneHue": return a["ColorGradeMidtoneSat"] > 0
        case "ColorGradeGlobalHue": return a["ColorGradeGlobalSat"] > 0
        case "ColorGradeBlending", "SplitToningBalance":
            return ["SplitToningShadowSaturation", "SplitToningHighlightSaturation", "ColorGradeMidtoneSat", "ColorGradeShadowLum", "ColorGradeMidtoneLum", "ColorGradeHighlightLum"].contains { a[$0] != 0 }
        default: return true
        }
    }
    public static func isNeutral(_ key: String, value: Double, in a: Adjustments) -> Bool {
        !isActive(key, in: a) || value == (defaults[key] ?? 0)
    }
}
