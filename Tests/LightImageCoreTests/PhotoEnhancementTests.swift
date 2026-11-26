import CoreImage
import XCTest
@testable import LightImageCore

final class PhotoEnhancementTests: XCTestCase {
    func testLensBlurSoftensTheBackgroundAndKeepsTheSubjectOpaqueAndSharp() throws {
        let engine = ImageEngine()
        let frame = CGRect(x: 0, y: 0, width: 240, height: 160)
        let backdrop = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 80, width: 240, height: 80))
            .composited(over: CIImage(color: .black).cropped(to: frame))
        let subject = CGRect(x: 85, y: 14, width: 70, height: 130)
        let source = CIImage(color: .red).cropped(to: subject).composited(over: backdrop)
        let maskImage = CIImage(color: .white).cropped(to: subject)
            .composited(over: CIImage(color: .black).cropped(to: frame))
        var edits = Adjustments()
        edits.lensBlurSubject = try png(maskImage, engine)
        edits[PhotoEnhancement.lensBlur.key] = 100

        let result = try engine.render(source, adjustments: edits)
        XCTAssertEqual(result.extent, frame)
        XCTAssertTrue(edits.isEdited)
        XCTAssertGreaterThan(pixel(result, 32, 79, engine)[0], 10)
        XCTAssertLessThan(pixel(result, 32, 80, engine)[0], 250)
        XCTAssertEqual(pixel(result, 115, 79, engine), pixel(source, 115, 79, engine))
        XCTAssertEqual(pixel(result, 85, 75, engine)[3], 255)
    }

    func testRestorationRemovesSmallSpecks() throws {
        let engine = ImageEngine()
        let frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        let base = CIImage(color: CIColor(red: 0.55, green: 0.55, blue: 0.55)).cropped(to: frame)
        let source = CIImage(color: .black).cropped(to: CGRect(x: 32, y: 29, width: 1, height: 1)).composited(over: base)
        var edits = Adjustments()
        edits[PhotoEnhancement.restore.key] = 100

        let restored = try engine.render(source, adjustments: edits)
        XCTAssertEqual(restored.extent, frame)
        XCTAssertEqual(pixel(restored, 32, 29, engine), pixel(restored, 35, 31, engine))
        XCTAssertGreaterThan(pixel(restored, 32, 29, engine)[0], pixel(source, 32, 29, engine)[0])
    }

    func testDetailEnhancementIncreasesLocalEdgeContrast() throws {
        let engine = ImageEngine()
        let frame = CGRect(x: 0, y: 0, width: 240, height: 120)
        let dark = CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35)).cropped(to: frame)
        let source = CIImage(color: CIColor(red: 0.50, green: 0.50, blue: 0.50))
            .cropped(to: CGRect(x: 120, y: 0, width: 120, height: 120)).composited(over: dark)
        var edits = Adjustments()
        edits[PhotoEnhancement.detail.key] = 100
        let detail = try engine.render(source, adjustments: edits)
        XCTAssertGreaterThan(pixel(detail, 120, 60, engine)[0] - pixel(detail, 119, 60, engine)[0],
                             pixel(source, 120, 60, engine)[0] - pixel(source, 119, 60, engine)[0])
    }

    func testLaMaGeneratesARepairInThePaintedAreaAndPersistsItForExport() async throws {
        guard let path = ProcessInfo.processInfo.environment["LIGHTIMAGE_LAMA_MODELS_DIR"] else {
            throw XCTSkip("Set LIGHTIMAGE_LAMA_MODELS_DIR to run the real LaMa model.")
        }
        let engine = ImageEngine()
        let frame = CGRect(x: 0, y: 0, width: 256, height: 180)
        let base = CIImage(color: CIColor(red: 0.15, green: 0.48, blue: 0.65)).cropped(to: frame)
        let source = CIImage(color: .red).cropped(to: CGRect(x: 62, y: 133, width: 16, height: 16)).composited(over: base)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        let originalBytes = try png(source, engine)
        try originalBytes.write(to: original)

        let model = GenerativeRemoval(modelDirectory: URL(fileURLWithPath: path, isDirectory: true))
        let stroke = LocalMask.BrushStroke(points: [CGPoint(x: 70.0 / 256, y: 141.0 / 180)], radius: 0.06, erases: false)
        let repair = try await model.repair(url: original, repairs: [], strokes: [stroke])
        var edits = Adjustments()
        edits.objectRepairs = [repair]
        let decoded = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
        XCTAssertTrue(decoded.isEdited)
        let exported = directory.appendingPathComponent("result.png")
        try engine.export(url: original, adjustments: decoded, destination: exported, format: "png")
        let result = try engine.load(url: exported)
        XCTAssertEqual(result.extent, frame)
        XCTAssertGreaterThan(pixel(result, 70, 141, engine)[1], 70)
        XCTAssertLessThan(pixel(result, 70, 141, engine)[0], 180)
        XCTAssertEqual(pixel(result, 70, 39, engine), pixel(base, 70, 39, engine))
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    private func png(_ image: CIImage, _ engine: ImageEngine) throws -> Data {
        try XCTUnwrap(engine.context.pngRepresentation(of: image, format: .RGBA8, colorSpace: engine.colorSpace))
    }

    private func pixel(_ image: CIImage, _ x: Int, _ y: Int, _ engine: ImageEngine) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: 4)
        engine.context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                              format: .RGBA8, colorSpace: engine.colorSpace)
        return bytes.map(Int.init)
    }
}
