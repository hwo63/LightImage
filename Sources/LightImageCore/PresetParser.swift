import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads preset data only. Legacy Lua expressions are never executed.
public enum PresetParser {
    public static let version = 4
    public static let colorNames = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
    public static let curveKeys: Set<String> = ["ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue", "ToneCurve"]
    public static let ranges: [String: ClosedRange<Double>] = {
        var r: [String: ClosedRange<Double>] = [
            "Exposure2012": -5...5, "Contrast2012": -100...100, "Highlights2012": -100...100,
            "Shadows2012": -100...100, "Whites2012": -100...100, "Blacks2012": -100...100,
            "Temperature": 2000...50000, "Tint": -150...150, "IncrementalTemperature": -100...100,
            "IncrementalTint": -100...100, "Vibrance": -100...100, "Saturation": -100...100,
            "Clarity2012": -100...100, "Texture": -100...100, "Sharpness": 0...150,
            "LuminanceSmoothing": 0...100, "PostCropVignetteAmount": -100...100,
            "VignetteAmount": -100...100
        ]
        for color in colorNames {
            for prefix in ["HueAdjustment", "SaturationAdjustment", "LuminanceAdjustment", "GrayMixer"] {
                r[prefix + color] = -100...100
            }
        }
        r.merge(PresetParameters.additionalRanges) { _, new in new }
        return r
    }()
    private static let aliases = ["Exposure": "Exposure2012", "Contrast": "Contrast2012", "Clarity": "Clarity2012"]
    private static let metadata: Set<String> = [
        "Name", "Group", "Description", "UUID", "Version", "ProcessVersion", "PresetType", "Cluster", "ShortName",
        "SortName", "SupportsAmount", "SupportsColor", "SupportsMonochrome", "SupportsHighDynamicRange",
        "SupportsNormalDynamicRange", "SupportsSceneReferred", "SupportsOutputReferred", "CameraModelRestriction",
        "Copyright", "ContactInfo", "HasSettings", "HasCrop", "AlreadyApplied", "RawFileName", "OverrideLookVignette",
        "ToneCurveName", "ToneCurveName2012", "WhiteBalance", "ConvertToGrayscale", "Treatment"
    ]

    public static func parse(url: URL) throws -> PhotoPreset {
        let data = try Data(contentsOf: url)
        guard data.count <= 16_000_000 else { throw LightImageError.invalidPreset(tr("Tệp vượt quá 16 MB.")) }
        var preset = try parse(data: data, filename: url.lastPathComponent)
        preset.sourcePath = url.standardizedFileURL.path
        return preset
    }

    public static func parse(data: Data, filename: String) throws -> PhotoPreset {
        guard data.count <= 16_000_000 else { throw LightImageError.invalidPreset(tr("Tệp vượt quá 16 MB.")) }
        var fields: [String: String]
        var arrays: [String: [String]]
        if filename.lowercased().hasSuffix(".lrtemplate") {
            guard let text = String(data: data, encoding: .utf8) else { throw LightImageError.invalidPreset(tr("Mã hóa không phải UTF-8.")) }
            var reader = LuaReader(text)
            let root = try reader.parse()
            let settings = root.object?["value"]?.object?["settings"]?.object ?? root.object?["settings"]?.object
            guard let settings else { throw LightImageError.invalidPreset(tr("Không tìm thấy bảng settings.")) }
            fields = settings.compactMapValues { $0.scalar }
            arrays = settings.compactMapValues { $0.array?.compactMap(\.scalar) }
            fields["Name"] = root.object?["title"]?.scalar ?? root.object?["name"]?.scalar
        } else {
            if String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("<!DOCTYPE") == true {
                throw LightImageError.invalidPreset(tr("XMP có khai báo DTD không được hỗ trợ."))
            }
            let delegate = XMPReader()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldReportNamespacePrefixes = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), delegate.hasCameraRaw else {
                throw LightImageError.invalidPreset(parser.parserError?.localizedDescription ?? tr("Không có dữ liệu Camera Raw trong XMP."))
            }
            fields = delegate.fields; arrays = delegate.arrays
        }
        var a = Adjustments()
        var unsupported = Set<String>()
        for (key, raw) in fields {
            let canonical = aliases[key] ?? key
            if let range = ranges[canonical] {
                let parsed = canonical == "AutoTone" ? (["true", "1"].contains(raw.lowercased()) ? 1.0 : ["false", "0"].contains(raw.lowercased()) ? 0.0 : nil) : Double(raw)
                guard let number = parsed, number.isFinite else {
                    throw LightImageError.invalidPreset(tr("Giá trị \(key) không hợp lệ."))
                }
                // A modern value takes precedence over its legacy equivalent.
                if aliases[key] != nil && fields[canonical] != nil { continue }
                a[canonical] = min(max(number, range.lowerBound), range.upperBound)
            } else if !metadata.contains(key) && !curveKeys.contains(key) {
                let neutral = Double(raw) == 0 || ["false", "", "none"].contains(raw.lowercased())
                let inactiveLensSetup = key == "LensProfileSetup" && (Double(fields["LensProfileEnable"] ?? "0") ?? 0) == 0
                let fringeParent = key.hasPrefix("DefringePurpleHue") ? "DefringePurpleAmount" : key.hasPrefix("DefringeGreenHue") ? "DefringeGreenAmount" : nil
                let inactiveFringe = fringeParent.map { (Double(fields[$0] ?? "0") ?? 0) == 0 } ?? false
                if !neutral && !inactiveLensSetup && !inactiveFringe { unsupported.insert(key) }
            }
        }
        for (key, raw) in arrays {
            if metadata.contains(key) { continue }
            guard curveKeys.contains(key) else { if !raw.isEmpty { unsupported.insert(key) }; continue }
            let numbers = raw.flatMap { $0.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Double($0) } }
            guard numbers.count >= 4, numbers.count % 2 == 0, numbers.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else {
                throw LightImageError.invalidPreset(tr("Đường cong \(key) không hợp lệ."))
            }
            var points: [CurvePoint] = []
            for i in stride(from: 0, to: numbers.count, by: 2) { points.append(.init(numbers[i] / 255, numbers[i + 1] / 255)) }
            points.sort { $0.x < $1.x }
            guard zip(points, points.dropFirst()).allSatisfy({ $0.x < $1.x }) else { throw LightImageError.invalidPreset(tr("Điểm đường cong bị trùng.")) }
            let target = key == "ToneCurve" ? "ToneCurvePV2012" : key
            if key == "ToneCurve" && arrays[target] != nil { continue }
            a.curves[target] = points
        }
        var mono: Bool?
        if let value = fields["ConvertToGrayscale"] { mono = value.lowercased() == "true" }
        if let treatment = fields["Treatment"] { mono = treatment.lowercased() == "black & white" }
        if let wb = fields["WhiteBalance"], !["custom", "as shot"].contains(wb.lowercased()), fields["Temperature"] == nil {
            unsupported.insert("WhiteBalance (\(wb))")
        }
        if fields["UUID"]?.uppercased() == TrongTreo3Calibration.presetUUID {
            a.trongTreo3Calibration = 1
        }
        var preset = PhotoPreset(name: fields["Name"].flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
                                 group: fields["Group"].flatMap { $0.isEmpty ? nil : $0 } ?? "Preset Lightroom",
                                 settings: a, monochrome: mono, unsupported: unsupported.sorted(), source: filename)
        guard preset.supportedCount > 0 || !preset.unsupported.isEmpty else { throw LightImageError.invalidPreset(tr("Không tìm thấy thông số chỉnh ảnh.")) }
        preset.sourceData = data; preset.parserVersion = version
        // Before Color Grading existed, Split Toning used fully overlapping tone ranges.
        if fields["ColorGradeBlending"] == nil && fields.keys.contains(where: { $0.hasPrefix("SplitToning") }) {
            preset.settings["ColorGradeBlending"] = 100
        }
        return preset
    }
}

private final class XMPReader: NSObject, XMLParserDelegate {
    var fields: [String: String] = [:]
    var arrays: [String: [String]] = [:]
    var hasCameraRaw = false
    private let namespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
    private var prefixes: Set<String> = ["crs"]
    private var stack: [(name: String, crs: Bool, text: String)] = []
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        if namespaceURI == namespace { prefixes.insert(prefix) }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let isCRS = namespaceURI == namespace
        if isCRS { hasCameraRaw = true }
        stack.append((elementName, isCRS, ""))
        // Nested Look/mask resources have their own Name/Exposure fields, not global adjustments.
        guard !stack.dropLast().contains(where: { $0.crs }) else { return }
        for (key, value) in attributeDict {
            let parts = key.split(separator: ":", maxSplits: 1)
            if parts.count == 2 && prefixes.contains(String(parts[0])) {
                hasCameraRaw = true; fields[String(parts[1])] = value
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !stack.isEmpty { stack[stack.count - 1].text += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let item = stack.popLast() else { return }
        let value = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTopLevel = !stack.contains(where: { $0.crs })
        if item.crs && isTopLevel && !value.isEmpty { fields[item.name] = value }
        if elementName == "li", stack.filter({ $0.crs }).count == 1, let parent = stack.last(where: { $0.crs }) {
            if ["Name", "Group", "Description", "Copyright", "ContactInfo"].contains(parent.name) {
                if fields[parent.name] == nil { fields[parent.name] = value }
            } else { arrays[parent.name, default: []].append(value) }
        }
        // Structured resources such as Look and MaskGroup must be reported even without scalar values.
        if item.crs && isTopLevel && value.isEmpty && !PresetParser.curveKeys.contains(item.name) && !["Name", "Group", "Description"].contains(item.name) {
            fields[item.name] = fields[item.name] ?? "[structured]"
        }
    }
}

private indirect enum LuaValue {
    case scalar(String), table([String: LuaValue], [LuaValue])
    var scalar: String? { if case .scalar(let s) = self { return s }; return nil }
    var object: [String: LuaValue]? { if case .table(let o, _) = self { return o }; return nil }
    var array: [LuaValue]? { if case .table(_, let a) = self { return a }; return nil }
}

private struct LuaReader {
    private var chars: [Character]
    private var index = 0
    init(_ text: String) { chars = Array(text) }
    mutating func skip() {
        while index < chars.count {
            if chars[index].isWhitespace || chars[index] == "," || chars[index] == ";" { index += 1 }
            else if chars[index] == "-" && index + 1 < chars.count && chars[index + 1] == "-" {
                while index < chars.count && chars[index] != "\n" { index += 1 }
            } else { break }
        }
    }
    mutating func parse() throws -> LuaValue {
        skip()
        if index < chars.count && chars[index] != "{" {
            _ = try token(); skip()
            guard index < chars.count && chars[index] == "=" else { throw failure() }
            index += 1
        }
        return try value(depth: 0)
    }
    func failure() -> LightImageError { .invalidPreset(tr("Cú pháp .lrtemplate không hợp lệ tại ký tự \(index).")) }
    mutating func token() throws -> String {
        skip(); guard index < chars.count else { throw failure() }
        let quote = chars[index]
        if quote == "\"" || quote == "'" {
            index += 1; var result = ""
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" {
                    index += 1; guard index < chars.count else { throw failure() }
                    switch chars[index] { case "n": result += "\n"; case "t": result += "\t"; case "r": result += "\r"; default: result.append(chars[index]) }
                } else { result.append(chars[index]) }
                index += 1
            }
            guard index < chars.count else { throw failure() }; index += 1; return result
        }
        let start = index
        while index < chars.count && !chars[index].isWhitespace && !["{", "}", "=", ",", ";", "[", "]"].contains(chars[index]) { index += 1 }
        guard index > start else { throw failure() }
        return String(chars[start..<index])
    }
    mutating func value(depth: Int) throws -> LuaValue {
        guard depth < 32 else { throw failure() }
        skip(); guard index < chars.count else { throw failure() }
        if chars[index] != "{" { return .scalar(try token()) }
        index += 1; var object: [String: LuaValue] = [:]; var array: [LuaValue] = []
        while true {
            skip(); guard index < chars.count else { throw failure() }
            if chars[index] == "}" { index += 1; return .table(object, array) }
            if chars[index] == "{" { array.append(try value(depth: depth + 1)); continue }
            var bracket = false
            if chars[index] == "[" { bracket = true; index += 1 }
            let key = try token(); skip()
            if bracket { guard index < chars.count && chars[index] == "]" else { throw failure() }; index += 1; skip() }
            if index < chars.count && chars[index] == "=" { index += 1; object[key] = try value(depth: depth + 1) }
            else { array.append(.scalar(key)) }
        }
    }
}
