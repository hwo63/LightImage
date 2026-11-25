import CoreImage
import XCTest
@testable import LightImageCore

final class LocalEditingTests: XCTestCase {
    private let engine = ImageEngine()
    private let extent = CGRect(x: 0, y: 0, width: 160, height: 100)

    func testGradientAndInversionAffectOppositeSides() throws {
        let source = gray()
        var mask = LocalMask(kind: .linear)
        mask.start = CGPoint(x: 0.25, y: 0.5)
        mask.end = CGPoint(x: 0.75, y: 0.5)
        mask.exposure = 0.7
        var edits = Adjustments()
        edits.localMasks = [mask]
        let output = try engine.render(source, adjustments: edits)
        let original = sample(source, 10, 50)
        XCTAssertGreaterThan(sample(output, 10, 50), original + 20)
        XCTAssertEqual(sample(output, 150, 50), original)
        edits.localMasks?[0].inverted = true
        let inverted = try engine.render(source, adjustments: edits)
        XCTAssertEqual(sample(inverted, 10, 50), original)
        XCTAssertGreaterThan(sample(inverted, 150, 50), original + 20)

        mask.kind = .radial
        mask.start = CGPoint(x: 0.5, y: 0.5)
        mask.end = CGPoint(x: 0.75, y: 0.5)
        edits.localMasks = [mask]
        let radial = try engine.render(source, adjustments: edits)
        XCTAssertGreaterThan(sample(radial, 80, 50), original + 20)
        XCTAssertEqual(sample(radial, 140, 50), original)
    }

    func testBrushAndEraserUseTheSameCoordinatesAfterFlip() throws {
        let source = gray()
        var mask = LocalMask(kind: .brush)
        mask.feather = 40
        mask.exposure = 0.75
        mask.strokes = [
            .init(points: [CGPoint(x: 0.20, y: 0.73), CGPoint(x: 0.47, y: 0.73)], radius: 0.08, erases: false),
            .init(points: [CGPoint(x: 0.30, y: 0.73)], radius: 0.05, erases: true)
        ]
        var edits = Adjustments()
        edits.localMasks = [mask]
        let baseline = sample(source, 73, 73)
        let painted = try engine.render(source, adjustments: edits)
        XCTAssertGreaterThan(sample(painted, 73, 73), baseline + 20)
        XCTAssertEqual(sample(painted, 48, 73), baseline)
        XCTAssertEqual(sample(painted, 73, 27), baseline)

        edits.flipHorizontal = true
        let flipped = try engine.render(source, adjustments: edits)
        XCTAssertGreaterThan(sample(flipped, 86, 73), baseline + 20)
        XCTAssertEqual(sample(flipped, 111, 73), baseline)
        let bytes = try JSONEncoder().encode(edits)
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: bytes), edits)
    }

    func testStraighteningPreservesAnOpaqueFrame() throws {
        var edits = Adjustments()
        edits["LightImageStraighten"] = 26
        let source = gray()
        let rotated = try engine.render(source, adjustments: edits)
        let w = Int(rotated.extent.width), h = Int(rotated.extent.height)
        XCTAssertLessThan(w, 160)
        XCTAssertEqual(Double(w) / Double(h), 1.6, accuracy: 0.06)
        for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
            XCTAssertEqual(sample(rotated, x, y, channel: 3), 255)
        }
    }

    func testImportedFilmControlsRenderDeterministically() throws {
        let xml = """
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:GrainAmount="75"
            crs:GrainSize="50" crs:GrainFrequency="40" crs:PostCropVignetteAmount="-50"
            crs:PostCropVignetteFeather="40"/>
        </rdf:RDF>
        """
        let preset = try PresetParser.parse(data: Data(xml.utf8), filename: "film.xmp")
        XCTAssertTrue(preset.unsupported.isEmpty)
        var edits = Adjustments()
        edits.apply(preset)
        let source = gray()
        let result = try engine.render(source, adjustments: edits)
        let repeated = try engine.render(source, adjustments: edits)
        let points = stride(from: 30, through: 130, by: 4)
        let grain = points.map { sample(result, $0, 50) }
        XCTAssertGreaterThan(Set(grain).count, 4)
        XCTAssertEqual(grain, points.map { sample(repeated, $0, 50) })
        XCTAssertLessThan(sample(result, 2, 2), sample(source, 2, 2) - 15)
    }

    private func gray() -> CIImage {
        CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35)).cropped(to: extent)
    }

    private func sample(_ image: CIImage, _ x: Int, _ y: Int, channel: Int = 0) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        engine.context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                              format: .RGBA8, colorSpace: engine.colorSpace)
        return Int(pixel[channel])
    }
}
