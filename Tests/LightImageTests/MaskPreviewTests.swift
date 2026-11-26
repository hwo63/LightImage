import AppKit
import CoreImage
import XCTest
import LightImageCore
@testable import LightImage

@MainActor
final class MaskPreviewTests: XCTestCase {
    func testPreviewUpdatesDuringSliderGestureAndAppliesFinalEditOnClose() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var photo = try makePhoto(in: directory, name: "wide", width: 320, height: 200)
        var mask = LocalMask(kind: .radial)
        mask.start = CGPoint(x: 0.25, y: 0.5)
        mask.end = CGPoint(x: 0.45, y: 0.5)
        photo.adjustments.localMasks = [mask]
        photo.adjustments.cropAspect = 1
        let model = AppModel(dataDirectory: directory)
        model.catalog.photos = [photo]
        model.select(photo.id)
        try await waitFor { model.preview != nil }

        model.maskSheet = true
        try await waitFor { model.maskPreview != nil }
        let initial = try XCTUnwrap(model.maskPreview)
        let initialCenter = try red(in: initial, x: 80)
        XCTAssertEqual(initial.size, NSSize(width: 320, height: 200))

        for tick in 1...30 {
            model.modifyMask(mask.id) { $0.exposure = Double(tick) / 30 }
            try await Task.sleep(for: .milliseconds(12))
        }
        let duringGesture = try XCTUnwrap(model.maskPreview)
        XCTAssertGreaterThan(try red(in: duringGesture, x: 80), initialCenter)
        XCTAssertEqual(try red(in: duringGesture, x: 290), try red(in: initial, x: 290), accuracy: 1.0 / 255)

        model.modifyMask(mask.id) { $0.exposure = 2 }
        let engine = ImageEngine()
        let source = try engine.load(url: URL(fileURLWithPath: photo.path), maxDimension: 2400)
        let expected = try engine.cgImage(engine.render(source, adjustments: model.edits, unframed: true))
        let finalRed = try red(in: NSImage(cgImage: expected, size: .zero), x: 80)
        try await waitFor {
            guard let image = model.maskPreview else { return false }
            return abs(try self.red(in: image, x: 80) - finalRed) < 1.0 / 255
        }

        model.endGesture("Phơi sáng")
        model.maskSheet = false
        XCTAssertNil(model.maskPreview)
        try await waitFor { !model.isRendering }
        let framed = try XCTUnwrap(model.preview)
        XCTAssertEqual(framed.size, NSSize(width: 200, height: 200))
        XCTAssertEqual(try red(in: framed, x: 20), finalRed, accuracy: 1.0 / 255)
    }

    func testSwitchingPhotoDropsPendingMaskPreviewForPreviousPhoto() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wide = try makePhoto(in: directory, name: "wide", width: 320, height: 200)
        let tall = try makePhoto(in: directory, name: "tall", width: 200, height: 320)
        let model = AppModel(dataDirectory: directory)
        model.catalog.photos = [wide, tall]
        model.select(wide.id)
        model.maskSheet = true
        model.update("Exposure2012", 1)
        model.select(tall.id)

        try await waitFor { model.maskPreview != nil }
        XCTAssertEqual(model.maskPreview?.size, NSSize(width: 200, height: 320))
    }

    private func waitFor(_ condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while try !condition() {
            guard ContinuousClock.now < deadline else { throw TestError.previewTimedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func red(in image: NSImage, x: Int) throws -> CGFloat {
        let raster = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let color = NSBitmapImageRep(cgImage: raster).colorAt(x: x, y: raster.height / 2)
        return try XCTUnwrap(color?.usingColorSpace(.sRGB)).redComponent
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePhoto(in directory: URL, name: String, width: Int, height: Int) throws -> PhotoRecord {
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return PhotoRecord(path: url.path)
    }

    private enum TestError: Error {
        case previewTimedOut
    }
}
