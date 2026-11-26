import XCTest
import CoreImage
@testable import LightImageCore

final class PortraitTests: XCTestCase {
    func testSelectedFaceRetouchProtectsOtherFacesAndEyes() throws {
        let engine = ImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        let plain = CIImage(color: CIColor(red: 0.63, green: 0.41, blue: 0.33)).cropped(to: extent)
        let left = PortraitSubject(face: CGRect(x: 0.08, y: 0.20, width: 0.32, height: 0.63),
                                   eyes: [CGRect(x: 0.14, y: 0.61, width: 0.08, height: 0.07)],
                                   lips: nil, waist: nil)
        let right = PortraitSubject(face: CGRect(x: 0.62, y: 0.20, width: 0.32, height: 0.63),
                                    eyes: [], lips: nil, waist: nil)
        let analysis = PortraitAnalysis(subjects: [left, right])
        let fleck = CIImage(color: CIColor(red: 0.70, green: 0.47, blue: 0.37))
            .cropped(to: CGRect(x: 46, y: 49, width: 1, height: 1))
        let source = fleck.composited(over: plain)
        var edits = Adjustments()
        edits.portraitFace = left.face
        edits[PortraitControl.brighten.key] = 80
        let bright = try engine.render(source, adjustments: edits, portrait: analysis)
        XCTAssertGreaterThan(pixel(bright, x: 48, y: 50, engine: engine)[0], pixel(source, x: 48, y: 50, engine: engine)[0] + 6)
        XCTAssertEqual(pixel(bright, x: 36, y: 64, engine: engine), pixel(source, x: 36, y: 64, engine: engine))
        XCTAssertEqual(pixel(bright, x: 156, y: 50, engine: engine), pixel(source, x: 156, y: 50, engine: engine))

        edits[PortraitControl.brighten.key] = 0
        edits[PortraitControl.smooth.key] = 100
        let smooth = try engine.render(source, adjustments: edits, portrait: analysis)
        XCTAssertLessThan(pixel(smooth, x: 46, y: 49, engine: engine)[0], pixel(source, x: 46, y: 49, engine: engine)[0] - 3)
        XCTAssertEqual(smooth.extent, extent)
    }

    func testWaistWarpNarrowsAContourAndKeepsPixelsOutsideTheRegion() throws {
        let engine = ImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 200, height: 160)
        let background = CIImage(color: .black).cropped(to: extent)
        let bar = CIImage(color: .white).cropped(to: CGRect(x: 70, y: 0, width: 60, height: 160))
        let source = bar.composited(over: background)
        var edits = Adjustments()
        edits.portraitWaist = PortraitWaist(center: CGPoint(x: 0.5, y: 0.5), width: 0.3)
        edits[PortraitControl.waistSlim.key] = 100
        let output = try engine.render(source, adjustments: edits, portrait: PortraitAnalysis(subjects: []))
        XCTAssertEqual(output.extent, extent)
        XCTAssertGreaterThan(pixel(source, x: 127, y: 80, engine: engine)[0], 245)
        XCTAssertLessThan(pixel(output, x: 127, y: 80, engine: engine)[0], 30)
        XCTAssertEqual(pixel(source, x: 127, y: 135, engine: engine), pixel(output, x: 127, y: 135, engine: engine))
    }

    func testArmAndLegControlsNarrowAcrossEachLimbIndependently() throws {
        let engine = ImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 320, height: 240)
        let arm = CIImage(color: .white).cropped(to: CGRect(x: 20, y: 125, width: 80, height: 20))
        let leg = CIImage(color: .white).cropped(to: CGRect(x: 210, y: 30, width: 30, height: 105))
        let source = arm.composited(over: leg.composited(over: CIImage(color: .black).cropped(to: extent)))
        let subject = PortraitSubject(face: CGRect(x: 0.4, y: 0.7, width: 0.16, height: 0.2), eyes: [], lips: nil, waist: nil,
            arms: [PortraitLimb(start: CGPoint(x: 20.0 / 320, y: 135.0 / 240), end: CGPoint(x: 100.0 / 320, y: 135.0 / 240))],
            legs: [PortraitLimb(start: CGPoint(x: 225.0 / 320, y: 30.0 / 240), end: CGPoint(x: 225.0 / 320, y: 135.0 / 240))])
        let analysis = PortraitAnalysis(subjects: [subject])
        var edits = Adjustments()
        edits[PortraitControl.armSlim.key] = 100
        let arms = try engine.render(source, adjustments: edits, portrait: analysis)
        XCTAssertLessThan(pixel(arms, x: 60, y: 143, engine: engine)[0], 30)
        XCTAssertEqual(pixel(arms, x: 24, y: 143, engine: engine), pixel(source, x: 24, y: 143, engine: engine))
        XCTAssertEqual(pixel(arms, x: 237, y: 82, engine: engine), pixel(source, x: 237, y: 82, engine: engine))

        edits[PortraitControl.armSlim.key] = 0
        edits[PortraitControl.legSlim.key] = 100
        let legs = try engine.render(source, adjustments: edits, portrait: analysis)
        XCTAssertLessThan(pixel(legs, x: 237, y: 82, engine: engine)[0], 30)
        XCTAssertEqual(pixel(legs, x: 60, y: 143, engine: engine), pixel(source, x: 60, y: 143, engine: engine))
        XCTAssertEqual(legs.extent, extent)
    }

    func testBlemishRemovalWorksWithoutSmoothingAndProtectsTheLips() throws {
        let engine = ImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 240, height: 200)
        let skin = CIImage(color: CIColor(red: 0.63, green: 0.41, blue: 0.33)).cropped(to: extent)
        let spot = CIImage(color: CIColor(red: 0.51, green: 0.14, blue: 0.16))
        let source = spot.cropped(to: CGRect(x: 94, y: 108, width: 3, height: 3)).composited(over:
            spot.cropped(to: CGRect(x: 119, y: 68, width: 3, height: 3)).composited(over: skin))
        let subject = PortraitSubject(face: CGRect(x: 0.2, y: 0.15, width: 0.60, height: 0.7), eyes: [],
                                      lips: CGRect(x: 0.45, y: 0.32, width: 0.1, height: 0.05), waist: nil)
        var edits = Adjustments()
        edits.updateFaceRetouch(for: nil) { $0.blemishes = 100 }
        XCTAssertEqual(edits.faceRetouch.settings(for: nil).smoothing, 0)
        let result = try engine.render(source, adjustments: edits, portrait: PortraitAnalysis(subjects: [subject]))
        XCTAssertGreaterThan(Int(pixel(result, x: 95, y: 109, engine: engine)[1]),
                             Int(pixel(source, x: 95, y: 109, engine: engine)[1]) + 35)
        XCTAssertEqual(pixel(result, x: 120, y: 69, engine: engine), pixel(source, x: 120, y: 69, engine: engine))
        XCTAssertEqual(pixel(result, x: 34, y: 109, engine: engine), pixel(source, x: 34, y: 109, engine: engine))
    }

    func testSelectingAnotherFacePreservesLegacyEditAndAppliesIndependentSettings() throws {
        let engine = ImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        let source = CIImage(color: CIColor(red: 0.63, green: 0.41, blue: 0.33)).cropped(to: extent)
        let left = PortraitSubject(face: CGRect(x: 0.08, y: 0.20, width: 0.32, height: 0.63), eyes: [], lips: nil, waist: nil)
        let right = PortraitSubject(face: CGRect(x: 0.62, y: 0.20, width: 0.32, height: 0.63), eyes: [], lips: nil, waist: nil)
        let analysis = PortraitAnalysis(subjects: [left, right])
        var edits = Adjustments()
        edits.portraitFace = left.face
        edits[PortraitControl.brighten.key] = 80
        edits[PortraitControl.smooth.key] = 20
        let legacy = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
        let original = try engine.render(source, adjustments: legacy, portrait: analysis)

        edits = legacy
        edits.selectPortraitFace(right.face)
        let selected = try engine.render(source, adjustments: edits, portrait: analysis)
        XCTAssertEqual(pixel(selected, x: 48, y: 50, engine: engine), pixel(original, x: 48, y: 50, engine: engine))
        XCTAssertEqual(edits.faceRetouch.settings(for: left.face).blemishes, 20)
        XCTAssertEqual(edits.faceRetouch.settings(for: right.face).brighten, 0)

        edits.updateFaceRetouch(for: right.face) {
            $0.brighten = 30
            $0.smoothing = 60
            $0.blemishes = 0
        }
        edits.selectPortraitFace(nil)
        let saved = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
        XCTAssertTrue(saved.isEdited)
        XCTAssertEqual(saved.faceRetouch.settings(for: nil).brighten, 0)
        XCTAssertEqual(saved.faceRetouch.settings(for: left.face).brighten, 80)
        XCTAssertEqual(saved.faceRetouch.settings(for: right.face).smoothing, 60)
        XCTAssertEqual(saved.faceRetouch.settings(for: right.face).blemishes, 0)
        XCTAssertEqual(ColorTreatment.settings(from: saved), Adjustments())
        let rendered = try engine.render(source, adjustments: saved, portrait: analysis)
        XCTAssertEqual(pixel(rendered, x: 48, y: 50, engine: engine), pixel(original, x: 48, y: 50, engine: engine))
        XCTAssertGreaterThan(pixel(rendered, x: 156, y: 50, engine: engine)[0], pixel(source, x: 156, y: 50, engine: engine)[0])

        edits.useCommonFaceRetouch(for: right.face)
        XCTAssertEqual(edits.faceRetouch.settings(for: right.face), edits.faceRetouch.settings(for: nil))
        XCTAssertEqual(edits.faceRetouch.settings(for: left.face).brighten, 80)
    }

    func testEditingAllFacesAppliesTheMovedControlToExistingAndNewFaceSettings() throws {
        let left = CGRect(x: 0.05, y: 0.2, width: 0.22, height: 0.6)
        let center = CGRect(x: 0.38, y: 0.2, width: 0.22, height: 0.6)
        let right = CGRect(x: 0.7, y: 0.2, width: 0.22, height: 0.6)
        var edits = Adjustments()
        edits.updateFaceRetouch(for: left) {
            $0.brighten = 80
            $0.slim = 25
        }
        edits.updateFaceRetouch(for: right) {
            $0.smoothing = 50
            $0.blemishes = 0
        }

        edits.updateFaceRetouch(for: nil) { $0.brighten = 40 }
        edits.updateFaceRetouch(for: nil) { $0.smoothing = 60 }
        let saved = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
        for face in [left, center, right] {
            XCTAssertEqual(saved.faceRetouch.settings(for: face).brighten, 40)
            XCTAssertEqual(saved.faceRetouch.settings(for: face).smoothing, 60)
        }
        XCTAssertEqual(saved.faceRetouch.settings(for: left).slim, 25)
        XCTAssertEqual(saved.faceRetouch.settings(for: left).blemishes, 60)
        XCTAssertEqual(saved.faceRetouch.settings(for: right).blemishes, 0)

        edits.updateFaceRetouch(for: nil) { $0.blemishes = 35 }
        edits.updateFaceRetouch(for: nil) { $0.slim = 0 }
        for face in [left, center, right] {
            XCTAssertEqual(edits.faceRetouch.settings(for: face).blemishes, 35)
            XCTAssertEqual(edits.faceRetouch.settings(for: face).slim, 0)
            XCTAssertFalse(edits.faceRetouch.hasOwnSettings(for: face))
        }
    }

    func testPortraitSettingsRoundTripAndDoNotChangeTheColorCube() throws {
        var edits = Adjustments()
        edits.portraitFace = CGRect(x: 0.2, y: 0.4, width: 0.15, height: 0.25)
        edits.portraitWaist = PortraitWaist(center: CGPoint(x: 0.3, y: 0.2), width: 0.2)
        edits[PortraitControl.faceSlim.key] = 45
        edits[PortraitControl.armSlim.key] = 22
        edits[PortraitControl.legSlim.key] = 38
        let decoded = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
        XCTAssertEqual(decoded, edits)
        XCTAssertTrue(decoded.isEdited)
        XCTAssertEqual(ColorTreatment.settings(from: edits), Adjustments())

        edits.keepPortrait(from: Adjustments())
        XCTAssertEqual(edits, Adjustments())
    }

    func testLocalGroupPhotoIfProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LIGHTIMAGE_PORTRAIT_FIXTURE"] else {
            throw XCTSkip("Set LIGHTIMAGE_PORTRAIT_FIXTURE to a local group photo.")
        }
        let engine = ImageEngine()
        let url = URL(fileURLWithPath: path)
        let source = try engine.load(url: url, maxDimension: 2400)
        let analysis = try engine.analyzePortrait(source)
        XCTAssertGreaterThan(analysis.subjects.count, 1)
        let subject = try XCTUnwrap(analysis.subjects.first)
        var edits = Adjustments()
        edits.selectPortraitFace(subject.face)
        edits.updateFaceRetouch(for: subject.face) {
            $0.brighten = 50
            $0.smoothing = 65
            $0.blemishes = 45
            $0.slim = 60
        }
        edits[PortraitControl.armSlim.key] = 45
        edits[PortraitControl.legSlim.key] = 40
        let output = try engine.cgImage(engine.render(source, adjustments: edits, portrait: analysis))
        XCTAssertEqual(output.width, Int(source.extent.width))
        XCTAssertEqual(output.height, Int(source.extent.height))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = folder.appendingPathComponent("group-edited.jpg")
        try engine.export(url: url, adjustments: edits, destination: result, format: "jpg")
        let exported = try engine.load(url: result)
        let original = try engine.load(url: url)
        XCTAssertEqual(exported.extent.size, original.extent.size)
        print("Portrait: \(analysis.subjects.count) faces, \(analysis.subjects.filter { $0.waist != nil }.count) auto waist regions")
    }

    private func pixel(_ image: CIImage, x: Int, y: Int, engine: ImageEngine) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 4)
        engine.context.render(image, toBitmap: &buffer, rowBytes: 4,
                              bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: engine.colorSpace)
        return buffer
    }
}
