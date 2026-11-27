import XCTest
import simd
import CoreImage
@testable import LightImageCore

final class ColorFidelityTests: XCTestCase {
    func testReferenceCalibrationFollowsPresetIdentityAndAmount() throws {
        func preset(_ id: String) throws -> PhotoPreset {
            let xml = """
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:UUID="\(id)" crs:Contrast2012="0"/></rdf:RDF>
            """
            return try PresetParser.parse(data: Data(xml.utf8), filename: "TRONG TRẺO 3.xmp")
        }
        let input = SIMD3(0.71, 0.49, 0.4)
        var a = Adjustments()
        a.apply(try preset(TrongTreo3Calibration.presetUUID), amount: 0.5)
        XCTAssertEqual(a.trongTreo3Calibration, 0.5)
        let treatment = ColorTreatment(ColorTreatment.settings(from: a))
        XCTAssertEqual(treatment.transform(.zero), .zero)
        XCTAssertEqual(treatment.transform(SIMD3(repeating: 1)), SIMD3(repeating: 1))
        let full = TrongTreo3Calibration.apply(to: input, strength: 1)
        XCTAssertGreaterThan(distance(input, full), 0.001)
        XCTAssertLessThan(distance(treatment.transform(input), (input + full) / 2), 1e-6)
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)), a)
        a.apply(try preset("different"))
        XCTAssertNil(a.trongTreo3Calibration)
    }

    func testBasicSlidersPreserveBlackAndChromaticity() {
        var a = Adjustments()
        a["Highlights2012"] = -100; a["Whites2012"] = -49
        a["Shadows2012"] = 15; a["Blacks2012"] = 18
        let treatment = ColorTreatment(a)
        XCTAssertEqual(treatment.transform(.zero), .zero, "Blacks must not add a grey floor")
        for input in [SIMD3(0.65,0.42,0.31), SIMD3(0.12,0.3,0.7), SIMD3(0.02,0.04,0.03)] {
            let output = treatment.transform(input)
            XCTAssertEqual(output.x / output.y, input.x / input.y, accuracy: 1e-6)
            XCTAssertEqual(output.z / output.y, input.z / input.y, accuracy: 1e-6)
            XCTAssertGreaterThan(output.y, 0)
        }
    }
    func testWhitesPreservesHighlightOrdering() {
        var a = Adjustments()
        a["Whites2012"] = -100
        let treatment = ColorTreatment(a)
        let samples = (0...255).map { treatment.basicTone(Double($0) / 255) }
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    func testSwitchingBetweenAutoAndManualTonePresets() {
        let keys = ["Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012"]
        var manual = Adjustments()
        for key in keys { manual[key] = 1 }
        var auto = Adjustments()
        auto["AutoTone"] = 1
        var edits = manual
        edits["HueAdjustmentBlue"] = 12
        edits.apply(PhotoPreset(name: "Auto", settings: auto))
        XCTAssertTrue(keys.allSatisfy { edits[$0] == 0 })
        XCTAssertEqual(edits["HueAdjustmentBlue"], 12)
        edits.apply(PhotoPreset(name: "Manual", settings: manual))
        XCTAssertEqual(edits["AutoTone"], 0)
        XCTAssertTrue(keys.allSatisfy { edits[$0] == 1 })
    }

    func testHSLBrightnessDoesNotLiftGrayAndKeepsHue() {
        var a = Adjustments()
        for color in PresetParser.colorNames { a["LuminanceAdjustment" + color] = 70 }
        let treatment = ColorTreatment(a)
        for value in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let out = treatment.transform(SIMD3(repeating: value))
            XCTAssertEqual(out.x, value, accuracy: 1e-6)
            XCTAssertEqual(out.y, value, accuracy: 1e-6)
            XCTAssertEqual(out.z, value, accuracy: 1e-6)
        }
        let input = SIMD3(0.12, 0.3, 0.16), out = treatment.transform(input)
        XCTAssertGreaterThan(ColorTreatment.luma(out), ColorTreatment.luma(input))
        XCTAssertEqual(ColorTreatment.rgbToHSL(input).x, ColorTreatment.rgbToHSL(out).x, accuracy: 1e-6)
        // Near-neutral colors must approach the neutral result continuously.
        let neutral = treatment.transform(SIMD3(0.3, 0.30001, 0.3))
        XCTAssertLessThan(abs(neutral.y - 0.30001), 1e-6)
    }
    func testCalibrationExtremesRemainFiniteAndPreserveWhitePoint() {
        for hue in [-100.0, 0, 100] { for red in [-100.0, 0, 100] { for blue in [-100.0, 0, 100] {
            var a = Adjustments()
            a["RedHue"] = hue; a["GreenHue"] = -hue; a["BlueHue"] = hue
            a["RedSaturation"] = red; a["GreenSaturation"] = -red; a["BlueSaturation"] = blue
            let treatment = ColorTreatment(a)
            for value in [0.02, 0.3, 0.8, 1] {
                let out = treatment.transform(SIMD3(repeating: value))
                XCTAssertEqual(out.x, value, accuracy: 1e-6)
                XCTAssertEqual(out.y, value, accuracy: 1e-6)
                XCTAssertEqual(out.z, value, accuracy: 1e-6)
            }
            for input in [SIMD3(1.0,0,0), SIMD3(0.0,1,0), SIMD3(0.0,0,1), SIMD3(0.8,0.4,0.3)] {
                let out = treatment.transform(input)
                for c in 0..<3 { XCTAssertTrue(out[c].isFinite && (0...1).contains(out[c])) }
            }
        } } }
    }
    func testRelativeWhiteBalanceHasCorrectDirectionAndNeutralIdentity() throws {
        let engine = ImageEngine()
        let source = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0,y: 0,width: 4,height: 4))
        func sample(_ a: Adjustments) throws -> [Float] {
            var data = [Float](repeating: 0, count: 4)
            let rendered = try engine.render(source, adjustments: a)
            engine.context.render(rendered, toBitmap: &data, rowBytes: 16, bounds: CGRect(x: 0,y: 0,width: 1,height: 1), format: .RGBAf, colorSpace: engine.colorSpace)
            return data
        }
        let neutral = try sample(Adjustments())
        XCTAssertEqual(neutral[0], neutral[1], accuracy: 0.0001)
        XCTAssertEqual(neutral[1], neutral[2], accuracy: 0.0001)
        var a = Adjustments(); a["IncrementalTemperature"] = 30
        let warm = try sample(a)
        a["IncrementalTemperature"] = -30
        let cool = try sample(a)
        XCTAssertGreaterThan(warm[0] / warm[2], cool[0] / cool[2])
        a["IncrementalTemperature"] = 0; a["IncrementalTint"] = 30
        let magenta = try sample(a)
        a["IncrementalTint"] = -30
        let green = try sample(a)
        XCTAssertGreaterThan((magenta[0] + magenta[2]) / magenta[1], (green[0] + green[2]) / green[1])
    }

    func testRawWhiteBalanceUsesCameraNeutralAndDecodesAtSelectedKelvin() throws {
        guard let path = ProcessInfo.processInfo.environment["LIGHTIMAGE_RAW_FIXTURE"] else {
            throw XCTSkip("Set LIGHTIMAGE_RAW_FIXTURE to a local RAW file.")
        }
        let engine = ImageEngine()
        let url = URL(fileURLWithPath: path)
        let source = try engine.loadSource(url: url, maxDimension: 480)
        let camera = try XCTUnwrap(source.rawWhiteBalance)
        let raw = try XCTUnwrap(CIRAWFilter(imageURL: url))
        XCTAssertEqual(camera.temperature, Double(raw.neutralTemperature))
        XCTAssertEqual(camera.tint, Double(raw.neutralTint))

        func pixels(_ image: CIImage) -> Data? {
            (try? engine.cgImage(image))?.dataProvider?.data as Data?
        }
        let asShot = try XCTUnwrap(pixels(source.image))
        var edits = Adjustments()
        edits["Temperature"] = camera.temperature
        edits["Tint"] = camera.tint
        XCTAssertEqual(try pixels(engine.render(source, adjustments: edits)), asShot)

        edits["Temperature"] = camera.temperature < 6500 ? 7400 : 3600
        edits["Tint"] = 0
        raw.neutralTemperature = Float(edits["Temperature"])
        raw.neutralTint = 0
        let expected = engine.resized(engine.normalized(try XCTUnwrap(raw.outputImage)), maxDimension: 480)
        let rendered = try engine.render(source, adjustments: edits)
        XCTAssertEqual(rendered.extent, source.image.extent)
        let actual = try XCTUnwrap(pixels(rendered))
        XCTAssertEqual(actual, try XCTUnwrap(pixels(expected)))
        XCTAssertNotEqual(actual, asShot)

        var halfStrength = Adjustments()
        halfStrength.apply(PhotoPreset(name: "Custom WB", settings: edits), amount: 0.5, rawWhiteBalance: camera)
        XCTAssertEqual(halfStrength["Temperature"], (camera.temperature + edits["Temperature"]) / 2)
        XCTAssertEqual(halfStrength["Tint"], camera.tint / 2)
    }
}
