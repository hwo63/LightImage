import Foundation

public struct CurvePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct Adjustments: Codable, Equatable, Sendable {
    public var values: [String: Double] = [:]
    public var curves: [String: [CurvePoint]] = [:]
    public var trongTreo3Calibration: Double?
    public var monochrome = false
    public var rotation = 0
    public var cropAspect: Double = 0
    public var cropScale: Double = 1
    public var cropX: Double = 0.5
    public var cropY: Double = 0.5
    public var portraitFace: CGRect?
    private var portraitRetouch: PortraitRetouch?
    public var portraitWaist: PortraitWaist?
    public var localMasks: [LocalMask]?
    public var lensBlurSubject: Data?
    public var objectRepairs: [ObjectRepair]?
    public var flipHorizontal: Bool?
    public var flipVertical: Bool?
    public init() {}
    public var hasPortraitEdits: Bool {
        faceRetouch.isEdited || self[PortraitControl.waistSlim.key] > 0 ||
        self[PortraitControl.armSlim.key] > 0 || self[PortraitControl.legSlim.key] > 0
    }
    var needsPortraitAnalysis: Bool {
        faceRetouch.isEdited || self[PortraitControl.armSlim.key] > 0 || self[PortraitControl.legSlim.key] > 0 ||
        (self[PortraitControl.waistSlim.key] > 0 && portraitWaist == nil)
    }
    public var faceRetouch: PortraitRetouch {
        if let portraitRetouch { return portraitRetouch }
        var legacy = PortraitRetouch.Settings()
        legacy.brighten = self[PortraitControl.brighten.key]
        legacy.smoothing = self[PortraitControl.smooth.key]
        legacy.slim = self[PortraitControl.faceSlim.key]
        var retouch = PortraitRetouch()
        retouch.set(legacy, for: portraitFace)
        return retouch
    }
    public mutating func selectPortraitFace(_ face: CGRect?) {
        if portraitRetouch == nil, faceRetouch.isEdited { storeFaceRetouch(faceRetouch) }
        portraitFace = face
        portraitWaist = nil
    }
    public mutating func updateFaceRetouch(for face: CGRect?, _ update: (inout PortraitRetouch.Settings) -> Void) {
        var retouch = faceRetouch
        retouch.update(for: face, update)
        storeFaceRetouch(retouch)
    }
    public mutating func useCommonFaceRetouch(for face: CGRect) {
        var retouch = faceRetouch
        retouch.useCommonSettings(for: face)
        storeFaceRetouch(retouch)
    }
    private mutating func storeFaceRetouch(_ retouch: PortraitRetouch) {
        portraitRetouch = retouch == PortraitRetouch() ? nil : retouch
        values.removeValue(forKey: PortraitControl.brighten.key)
        values.removeValue(forKey: PortraitControl.smooth.key)
        values.removeValue(forKey: PortraitControl.faceSlim.key)
    }
    public mutating func keepPortrait(from source: Adjustments) {
        portraitFace = source.portraitFace
        portraitRetouch = source.portraitRetouch
        portraitWaist = source.portraitWaist
        for control in PortraitControl.allCases { values[control.key] = source.values[control.key] }
    }
    public mutating func keepLocalEdits(from source: Adjustments) {
        localMasks = source.localMasks
        objectRepairs = source.objectRepairs
        lensBlurSubject = source.lensBlurSubject
        values[PhotoEnhancement.lensBlur.key] = source.values[PhotoEnhancement.lensBlur.key]
    }
    public subscript(_ key: String) -> Double {
        get { values[key] ?? PresetParameters.defaults[key] ?? 0 }
        set { values[key] = newValue }
    }
    public var isEdited: Bool {
        hasPortraitEdits || (trongTreo3Calibration ?? 0) > 0 || values["Tint"] != nil ||
        values.contains { !PresetParameters.isNeutral($0.key, value: $0.value, in: self) } ||
        objectRepairs?.isEmpty == false ||
        !curves.isEmpty || monochrome || rotation % 4 != 0 || cropAspect != 0 || cropScale != 1 ||
        flipHorizontal == true || flipVertical == true || (localMasks?.contains(where: \.isActive) ?? false)
    }
    public mutating func apply(_ preset: PhotoPreset, amount: Double = 1, rawWhiteBalance: RawWhiteBalance? = nil) {
        let strength = min(max(amount, 0), 1)
        guard strength > 0 else { return }
        let oldCalibration = trongTreo3Calibration ?? 0
        let newCalibration = preset.settings.trongTreo3Calibration ?? 0
        let calibration = oldCalibration * (1 - strength) + newCalibration * strength
        trongTreo3Calibration = calibration > 0 ? calibration : nil
        // Auto settings replace the previous basic tone solution. Otherwise a
        // full manual preset applied after Auto would still render through Auto.
        let basicKeys = ["Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012"]
        let incoming = preset.settings.values
        if incoming["AutoTone"] == 1 {
            for key in basicKeys where incoming[key] == nil && values[key] != nil {
                self[key] *= 1 - strength
            }
        } else if incoming["AutoTone"] == nil && basicKeys.allSatisfy({ incoming[$0] != nil }) {
            values.removeValue(forKey: "AutoTone")
        }
        for (key, value) in preset.settings.values {
            let baseline: Double
            switch key {
            case "Temperature" where self[key] <= 0: baseline = rawWhiteBalance?.temperature ?? 6500
            case "Tint" where values[key] == nil: baseline = rawWhiteBalance?.tint ?? 0
            default: baseline = self[key]
            }
            if key == "AutoTone" { self[key] = value }
            else if PresetParameters.circular.contains(key) {
                let distance = (value - baseline + 540).truncatingRemainder(dividingBy: 360) - 180
                self[key] = (baseline + distance * strength + 360).truncatingRemainder(dividingBy: 360)
            } else { self[key] = baseline + (value - baseline) * strength }
        }
        for (key, points) in preset.settings.curves {
            let previous = curves[key]
            curves[key] = points.map {
                let before = ImageEngine.curve($0.x, previous)
                return CurvePoint($0.x, before + ($0.y - before) * strength)
            }
        }
        if let mono = preset.monochrome { monochrome = mono }
    }
}

public struct PhotoPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var group: String
    public var settings: Adjustments
    public var monochrome: Bool?
    public var unsupported: [String]
    public var source: String
    public var sourceData: Data?
    public var sourcePath: String?
    public var parserVersion: Int?
    public var supportedCount: Int { settings.values.count + settings.curves.count + (monochrome == nil ? 0 : 1) }
    public init(name: String, group: String = "Đã nhập", settings: Adjustments, monochrome: Bool? = nil, unsupported: [String] = [], source: String = "LightImage") {
        id = UUID(); self.name = name; self.group = group; self.settings = settings
        self.monochrome = monochrome; self.unsupported = unsupported; self.source = source
    }
    public static var builtins: [PhotoPreset] {
        func make(_ name: String, _ values: [String: Double], mono: Bool? = nil, curve: [CurvePoint]? = nil) -> PhotoPreset {
            var a = Adjustments(); a.values = values
            if let curve { a.curves["ToneCurvePV2012"] = curve }
            return PhotoPreset(name: name, group: "LightImage Essentials", settings: a, monochrome: mono)
        }
        return [
            make("01 · Soft daylight", ["Exposure2012": 0.2, "Contrast2012": -12, "Highlights2012": -30, "Shadows2012": 22, "Vibrance": 12]),
            make("02 · Golden hour", ["IncrementalTemperature": 16, "Highlights2012": -25, "Shadows2012": 12, "Vibrance": 20, "Saturation": -5]),
            make("03 · Quiet cinema", ["Contrast2012": 18, "Saturation": -22, "HueAdjustmentBlue": -18, "LuminanceAdjustmentBlue": -15], curve: [.init(0, 0.055), .init(0.25, 0.2), .init(0.5, 0.48), .init(0.75, 0.8), .init(1, 0.96)]),
            make("04 · Silver & shadow", ["Contrast2012": 25, "Highlights2012": -18, "Shadows2012": 12, "Clarity2012": 12], mono: true),
            make("05 · Botanical", ["HueAdjustmentGreen": -18, "SaturationAdjustmentGreen": -20, "LuminanceAdjustmentGreen": -12, "Vibrance": 18]),
            make("06 · Clean portrait", ["Exposure2012": 0.15, "Texture": -18, "Highlights2012": -20, "LuminanceAdjustmentOrange": 12, "SaturationAdjustmentOrange": -8])
        ]
    }
}

public struct PhotoRecord: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var path: String
    public var rating = 0
    public var flagged = false
    public var adjustments = Adjustments()
    public var importedAt = Date()
    public var copyNumber: Int?
    public var name: String {
        let url = URL(fileURLWithPath: path)
        guard let copyNumber else { return url.lastPathComponent }
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        return tr("\(stem) (Bản sao \(copyNumber))\(suffix)")
    }
    public init(path: String) { self.path = path }
}

public struct Catalog: Codable {
    public var version = 1
    public var photos: [PhotoRecord] = []
    public var presets: [PhotoPreset] = []
    public init() {}
    /// Reimport upgrades an existing preset without changing its identity or editing any photos.
    @discardableResult public mutating func mergePreset(_ preset: PhotoPreset) -> Bool {
        let existing = presets.firstIndex { old in
            if let lhs = old.sourcePath, let rhs = preset.sourcePath { return lhs == rhs }
            return old.source.precomposedStringWithCanonicalMapping == preset.source.precomposedStringWithCanonicalMapping && old.name == preset.name && old.group == preset.group
        }
        if let index = existing {
            var updated = preset; updated.id = presets[index].id; presets[index] = updated
            return false
        }
        presets.append(preset); return true
    }
}

public enum LightImageError: LocalizedError {
    case invalidPreset(String), unreadableImage(String), exportFailed(String)
    case portraitFailed
    public var errorDescription: String? {
        switch self {
        case .invalidPreset(let reason): return tr("Không đọc được preset: \(reason)")
        case .unreadableImage(let name): return tr("Không thể mở ảnh \(name). Định dạng RAW có thể chưa được macOS hỗ trợ.")
        case .exportFailed(let name): return tr("Không thể xuất ảnh: \(name)")
        case .portraitFailed: return tr("Không thể xử lý vùng chân dung trên ảnh này.")
        }
    }
}
