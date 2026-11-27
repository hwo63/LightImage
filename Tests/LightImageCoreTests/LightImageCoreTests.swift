import XCTest
import CoreImage
import ImageIO
@testable import LightImageCore

final class LightImageCoreTests: XCTestCase {
    func testInterfaceTextTranslatesTemplatesAndPreservesUserData() {
        let presetName = "Màu nhà tôi %@"
        let message: InterfaceText = "Đã áp dụng \(presetName) cho \(3) ảnh đã chọn"
        XCTAssertEqual(message.localized(.vietnamese), "Đã áp dụng \(presetName) cho 3 ảnh đã chọn")
        XCTAssertEqual(message.localized(.english), "Applied \(presetName) to 3 selected photos")
        let zoom: InterfaceText = "\(150)% so với vừa khung"
        XCTAssertEqual(zoom.localized(.english), "150% of fit")
        let missing: InterfaceText = "Thiếu bản dịch \(2)"
        XCTAssertEqual(missing.localized(.english), "Thiếu bản dịch 2")
    }

    func xmp(_ body: String, attributes: String = "") -> Data {
        Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" \(attributes)>\(body)</rdf:Description></rdf:RDF></x:xmpmeta>
        """.utf8)
    }
    func testXMPAttributesLocalizedNameCurvesAndUnsupported() throws {
        let data = xmp("""
        <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Warm &amp; soft</rdf:li></rdf:Alt></crs:Name>
        <crs:Group><rdf:Alt><rdf:li>Travel</rdf:li></rdf:Alt></crs:Group>
        <crs:ShortName><rdf:Alt><rdf:li>Warm</rdf:li></rdf:Alt></crs:ShortName>
        <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 15</rdf:li><rdf:li>128, 140</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
        <crs:Look><rdf:Description crs:Name="Film Look" crs:Amount="1"/></crs:Look>
        """, attributes: "crs:Exposure2012=\"0.65\" crs:Highlights2012=\"-40\" crs:CameraProfile=\"Adobe Color\" crs:ConvertToGrayscale=\"False\"")
        let preset = try PresetParser.parse(data: data, filename: "test.xmp")
        XCTAssertEqual(preset.name, "Warm & soft")
        XCTAssertEqual(preset.group, "Travel")
        XCTAssertEqual(preset.settings["Exposure2012"], 0.65)
        XCTAssertEqual(preset.settings["Highlights2012"], -40)
        XCTAssertEqual(preset.settings.curves["ToneCurvePV2012"]?.count, 3)
        XCTAssertEqual(preset.monochrome, false)
        XCTAssertTrue(preset.unsupported.contains("CameraProfile"))
        XCTAssertTrue(preset.unsupported.contains("Look"))
        XCTAssertFalse(preset.unsupported.contains("ShortName"))
    }
    func testAlternateNamespaceAndElementValues() throws {
        let data = Data("""
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:camera="http://ns.adobe.com/camera-raw-settings/1.0/"><rdf:Description camera:Exposure2012="1.1"><camera:Contrast2012>23</camera:Contrast2012></rdf:Description></rdf:RDF>
        """.utf8)
        let p = try PresetParser.parse(data: data, filename: "alternate.xmp")
        XCTAssertEqual(p.settings["Exposure2012"], 1.1)
        XCTAssertEqual(p.settings["Contrast2012"], 23)
    }
    func testLegacyLuaSettingsAndNumericCurveArray() throws {
        let text = """
        -- Lightroom preset; data only
        s = { id = "123", title = "Màu nắng", type = "Develop", value = {
          settings = { Exposure2012 = 0.4, Contrast2012 = 12, ConvertToGrayscale = false,
          ToneCurvePV2012 = { 0, 10, 128, 120, 255, 249, },
          HueAdjustmentGreen = -20, CameraProfile = "Adobe Standard", }, }, }
        """
        let p = try PresetParser.parse(data: Data(text.utf8), filename: "warm.lrtemplate")
        XCTAssertEqual(p.name, "Màu nắng")
        XCTAssertEqual(p.settings["Exposure2012"], 0.4)
        XCTAssertEqual(p.settings["HueAdjustmentGreen"], -20)
        XCTAssertEqual(p.settings.curves["ToneCurvePV2012"]?.last?.y ?? 0, 249.0 / 255, accuracy: 0.0001)
        XCTAssertTrue(p.unsupported.contains("CameraProfile"))
    }
    func testMalformedDataIsRejected() {
        XCTAssertThrowsError(try PresetParser.parse(data: Data("not xml".utf8), filename: "bad.xmp"))
        XCTAssertThrowsError(try PresetParser.parse(data: xmp("", attributes: "crs:Exposure2012=\"nan\""), filename: "bad.xmp"))
        XCTAssertThrowsError(try PresetParser.parse(data: xmp("<crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>0, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>"), filename: "bad.xmp"))
        XCTAssertThrowsError(try PresetParser.parse(data: Data("s = { value = { settings = { Exposure2012 = os.execute('bad') } } }".utf8), filename: "bad.lrtemplate"))
        XCTAssertThrowsError(try PresetParser.parse(data: Data("<!DOCTYPE x [<!ENTITY a SYSTEM 'file:///tmp/secret'>]><x/>".utf8), filename: "bad.xmp"))
    }
    func testPartialPresetPreservesAbsentFieldsAndZeroAmount() throws {
        let preset = try PresetParser.parse(data: xmp("", attributes: "crs:Exposure2012=\"1\" crs:ConvertToGrayscale=\"True\""), filename: "partial.xmp")
        var base = Adjustments(); base["Saturation"] = 31; base.cropAspect = 1
        let original = base
        base.apply(preset, amount: 0)
        XCTAssertEqual(base, original)
        base.apply(preset)
        XCTAssertEqual(base["Exposure2012"], 1)
        XCTAssertEqual(base["Saturation"], 31)
        XCTAssertEqual(base.cropAspect, 1)
        XCTAssertTrue(base.monochrome)
    }
    func testModernValueTakesPrecedenceAndClamps() throws {
        let p = try PresetParser.parse(data: xmp("", attributes: "crs:Exposure=\"2\" crs:Exposure2012=\"0.5\" crs:Vibrance=\"999\""), filename: "test.xmp")
        XCTAssertEqual(p.settings["Exposure2012"], 0.5)
        XCTAssertEqual(p.settings["Vibrance"], 100)
    }
    func testCatalogRoundTrip() throws {
        var c = Catalog(); var photo = PhotoRecord(path: "/tmp/example.jpg")
        photo.rating = 4; photo.flagged = true; photo.adjustments["Exposure2012"] = 0.7
        c.photos = [photo]; c.presets = PhotoPreset.builtins
        let restored = try JSONDecoder().decode(Catalog.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(restored.photos.first?.adjustments, photo.adjustments)
        XCTAssertEqual(restored.photos.first?.rating, 4)
        XCTAssertEqual(restored.photos.first?.flagged, true)
        XCTAssertEqual(restored.presets, c.presets)
    }
    func testImportedPresetChangesRenderedPixels() throws {
        let engine = ImageEngine()
        let source = CIImage(color: CIColor(red: 0.25, green: 0.36, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        let preset = try PresetParser.parse(data: xmp("", attributes: "crs:Exposure2012=\"1\" crs:Saturation=\"-100\""), filename: "test.xmp")
        var a = Adjustments(); a.apply(preset)
        let before = pixel(engine, source)
        let after = try pixel(engine, engine.render(source, adjustments: a))
        XCTAssertGreaterThan(after[0], before[0] + 20)
        XCTAssertLessThanOrEqual(abs(Int(after[0]) - Int(after[1])), 3)
        XCTAssertLessThanOrEqual(abs(Int(after[1]) - Int(after[2])), 3)
    }
    func testNeutralPipelineAndGeometry() throws {
        let engine = ImageEngine()
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7)).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
        var zero = Adjustments(); zero["Contrast2012"] = 0
        let original = pixel(engine, source), neutral = try pixel(engine, engine.render(source, adjustments: zero))
        for c in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(original[c]) - Int(neutral[c])), 2) }
        zero.rotation = 1
        XCTAssertEqual(try engine.render(source, adjustments: zero).extent.size, CGSize(width: 80, height: 120))
        zero.cropAspect = 1; zero.cropScale = 0.5
        XCTAssertEqual(try engine.render(source, adjustments: zero).extent.size, CGSize(width: 40, height: 40))
    }
    func testExportJPEGPNGAnd16BitTIFFPreservesOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = ImageEngine(), sourceURL = directory.appendingPathComponent("source.png")
        let source = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 80))
        try engine.context.writePNGRepresentation(of: source, to: sourceURL, format: .RGBA8, colorSpace: engine.colorSpace)
        let original = try Data(contentsOf: sourceURL)
        var a = Adjustments(); a["Exposure2012"] = 0.4; a.cropAspect = 1
        for format in ["jpg", "png", "tiff"] {
            let output = directory.appendingPathComponent("out.\(format)")
            try engine.export(url: sourceURL, adjustments: a, destination: output, format: format, maxDimension: 40)
            let reader = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(reader, 0, nil))
            XCTAssertEqual(cg.width, 40); XCTAssertEqual(cg.height, 40)
            if format == "tiff" { XCTAssertEqual(cg.bitsPerComponent, 16) }
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(reader, 0, nil) as? [String: Any])
            if format == "jpg" {
                let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
                XCTAssertEqual(exif[kCGImagePropertyExifColorSpace as String] as? Int, 1)
            }
            if format == "png" {
                let png = try XCTUnwrap(properties[kCGImagePropertyPNGDictionary as String] as? [String: Any])
                XCTAssertEqual(png[kCGImagePropertyPNGsRGBIntent as String] as? Int, 0)
            }
            // Exercise atomic overwrite of an already exported destination.
            try engine.export(url: sourceURL, adjustments: a, destination: output, format: format)
        }
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
    }
    private func pixel(_ engine: ImageEngine, _ image: CIImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 4)
        engine.context.render(image, toBitmap: &result, rowBytes: 4, bounds: CGRect(x: 1, y: 1, width: 1, height: 1), format: .RGBA8, colorSpace: engine.colorSpace)
        return result
    }
}
