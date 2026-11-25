import CoreImage
import ImageIO
import XCTest
@testable import LightImageCore

final class AutomaticMaskTests: XCTestCase {
    private let engine = ImageEngine()
    private let extent = CGRect(x: 0, y: 0, width: 160, height: 100)

    func testSkySelectsTopAndRejectsDisconnectedBlue() throws {
        let land = CIImage(color: CIColor(red: 0.18, green: 0.38, blue: 0.16)).cropped(to: extent)
        let blue = CIImage(color: CIColor(red: 0.31, green: 0.62, blue: 0.88))
        let sky = blue.cropped(to: CGRect(x: 0, y: 64, width: 160, height: 36))
        let pond = blue.cropped(to: CGRect(x: 32, y: 8, width: 55, height: 17))
        let ridge = CIImage(color: CIColor(red: 0.27, green: 0.49, blue: 0.57))
            .cropped(to: CGRect(x: 90, y: 40, width: 40, height: 38))
        let source = ridge.composited(over: sky.composited(over: pond.composited(over: land)))
        var mask = LocalMask(kind: .sky)
        mask.automaticPNG = try engine.detectMask(.sky, in: source)
        mask.feather = 0
        mask.exposure = -1
        var edits = Adjustments()
        edits.localMasks = [mask]
        let image = try engine.render(source, adjustments: edits)
        XCTAssertLessThan(sample(image, x: 48, y: 85), sample(source, x: 48, y: 85) - 15)
        XCTAssertEqual(sample(image, x: 48, y: 15), sample(source, x: 48, y: 15))
        XCTAssertEqual(sample(image, x: 48, y: 45), sample(source, x: 48, y: 45))
        XCTAssertEqual(sample(image, x: 105, y: 71), sample(source, x: 105, y: 71))

        XCTAssertThrowsError(try engine.detectMask(.sky, in: land)) {
            XCTAssertEqual($0 as? AutomaticMaskError, .noSky)
        }

        let overlay = CIImage(cgImage: try engine.automaticMaskOverlay(mask))
        XCTAssertGreaterThan(sample(overlay, x: 48, y: 85, channel: 3), 100)
        XCTAssertEqual(sample(overlay, x: 48, y: 15, channel: 3), 0)
    }

    func testSavedForegroundBitmapIsSharedAndInvertsAtExportScale() throws {
        let half = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 10))
            .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20)))
        let bitmap = try XCTUnwrap(engine.context.pngRepresentation(of: half, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()))
        let source = CIImage(color: CIColor(red: 0.42, green: 0.42, blue: 0.42)).cropped(to: extent)
        var edits = Adjustments()
        var mask = LocalMask(kind: .subject)
        mask.automaticPNG = bitmap
        mask.feather = 0
        mask.exposure = 0.85
        edits.localMasks = [mask]
        let restored = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
        let subject = try engine.render(source, adjustments: restored)
        XCTAssertEqual(restored, edits)
        let original = sample(source, x: 80, y: 25)
        XCTAssertGreaterThan(sample(subject, x: 80, y: 25), original + 15)
        XCTAssertEqual(sample(subject, x: 80, y: 75), original)

        mask.kind = .background
        edits.localMasks = [mask]
        edits.flipVertical = true
        let background = try engine.render(source, adjustments: edits)
        XCTAssertGreaterThan(sample(background, x: 80, y: 25), original + 15)
        XCTAssertEqual(sample(background, x: 80, y: 75), original)
    }

    func testVisionWithLocalGroupPhotoIfProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LIGHTIMAGE_PORTRAIT_FIXTURE"] else {
            throw XCTSkip("Set LIGHTIMAGE_PORTRAIT_FIXTURE to test Vision masks on a local photo.")
        }
        let url = URL(fileURLWithPath: path)
        let source = try engine.load(url: url, maxDimension: 1200)
        var subject = LocalMask(kind: .subject)
        subject.automaticPNG = try engine.detectMask(.subject, in: source)
        subject.feather = 15
        subject.exposure = 0.7
        let coverage = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(subject, extent: source.extent))
        let center = sample(coverage, x: Int(source.extent.width * 0.52), y: Int(source.extent.height * 0.41))
        let corner = sample(coverage, x: Int(source.extent.width * 0.1), y: Int(source.extent.height * 0.92))
        XCTAssertGreaterThan(center, 180)
        XCTAssertLessThan(corner, 75)

        subject.strokes = [
            .init(points: [CGPoint(x: 0.52, y: 0.41)], radius: 0.035, erases: true),
            .init(points: [CGPoint(x: 0.1, y: 0.92)], radius: 0.035, erases: false)
        ]
        var edits = Adjustments(); edits.localMasks = [subject]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = folder.appendingPathComponent("masked.jpg")
        try engine.export(url: url, adjustments: edits, destination: result, format: "jpg")
        let exported = try engine.load(url: result)
        let original = try engine.load(url: url)
        XCTAssertEqual(exported.extent.size, original.extent.size)
        let erased = CGPoint(x: original.extent.width * 0.52, y: original.extent.height * 0.41)
        let added = CGPoint(x: original.extent.width * 0.1, y: original.extent.height * 0.92)
        XCTAssertEqual(sample(exported, x: Int(erased.x), y: Int(erased.y)),
                       sample(original, x: Int(erased.x), y: Int(erased.y)), accuracy: 10)
        XCTAssertGreaterThan(sample(exported, x: Int(added.x), y: Int(added.y)),
                             sample(original, x: Int(added.x), y: Int(added.y)) + 10)
    }

    func testAutomaticBrushCorrectionsSurviveSaveAndMatchOverlay() throws {
        let lower = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 10))
            .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20)))
        let bitmap = try XCTUnwrap(engine.context.pngRepresentation(of: lower, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()))
        let source = CIImage(color: CIColor(red: 0.42, green: 0.42, blue: 0.42)).cropped(to: extent)
        let baseline = sample(source, x: 80, y: 25)

        for kind in [LocalMask.Kind.sky, .subject, .background] {
            let lowerSelected = kind != .background
            let eraseY = lowerSelected ? 0.25 : 0.75
            let paintY = 1 - eraseY
            var mask = LocalMask(kind: kind)
            mask.automaticPNG = bitmap
            mask.feather = 15
            mask.exposure = 0.85
            mask.strokes = [
                .init(points: [CGPoint(x: 0.5, y: eraseY)], radius: 0.08, erases: true),
                .init(points: [CGPoint(x: 0.5, y: paintY)], radius: 0.08, erases: false),
                .init(points: [CGPoint(x: 0.5, y: paintY)], radius: 0.02, erases: true)
            ]
            var edits = Adjustments(); edits.localMasks = [mask]
            let saved = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edits))
            let rendered = try engine.render(source, adjustments: saved)
            XCTAssertEqual(saved, edits)
            XCTAssertEqual(sample(rendered, x: 80, y: Int(eraseY * 100)), baseline)
            XCTAssertEqual(sample(rendered, x: 80, y: Int(paintY * 100)), baseline)
            XCTAssertGreaterThan(sample(rendered, x: 88, y: Int(paintY * 100)), baseline + 15)
            XCTAssertGreaterThan(sample(rendered, x: 20, y: Int(eraseY * 100)), baseline + 15)

            let overlay = CIImage(cgImage: try engine.automaticMaskOverlay(mask))
            func alpha(_ x: Double, _ y: Double) -> Int {
                sample(overlay, x: Int(overlay.extent.width * x), y: Int(overlay.extent.height * y), channel: 3)
            }
            XCTAssertEqual(alpha(0.5, eraseY), 0)
            XCTAssertEqual(alpha(0.5, paintY), 0)
            XCTAssertGreaterThan(alpha(0.55, paintY), 105)

            mask.inverted = true
            let invertedOverlay = CIImage(cgImage: try engine.automaticMaskOverlay(mask))
            XCTAssertGreaterThan(sample(invertedOverlay, x: 600, y: Int(1200 * eraseY), channel: 3), 105)
        }
    }

    func testBrushStrengthAndSoftnessApplyPerStroke() throws {
        let base = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 80, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        var mask = LocalMask(kind: .subject)
        mask.automaticPNG = try XCTUnwrap(engine.context.pngRepresentation(of: base, format: .L8,
                                                                          colorSpace: CGColorSpaceCreateDeviceGray()))
        mask.feather = 0
        mask.strokes = [
            .init(points: [CGPoint(x: 0.25, y: 0.5)], radius: 0.13, erases: true, softness: 85, strength: 25),
            .init(points: [CGPoint(x: 0.75, y: 0.5)], radius: 0.13, erases: false, softness: 85, strength: 40),
            .init(points: [CGPoint(x: 0.75, y: 0.18)], radius: 0.13, erases: false, softness: 0, strength: 40)
        ]
        let restored = try JSONDecoder().decode(LocalMask.self, from: JSONEncoder().encode(mask))
        XCTAssertEqual(restored, mask)
        let coverage = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(restored, extent: extent))
        XCTAssertEqual(sample(coverage, x: 40, y: 50), 191, accuracy: 4)
        XCTAssertEqual(sample(coverage, x: 120, y: 50), 102, accuracy: 4)
        XCTAssertEqual(sample(coverage, x: 120, y: 18), 102, accuracy: 4)
        XCTAssertLessThan(sample(coverage, x: 135, y: 50), 52)
        XCTAssertEqual(sample(coverage, x: 135, y: 18), 102, accuracy: 4)
        XCTAssertGreaterThan(sample(coverage, x: 55, y: 50), 220)

        let legacy = Data(#"{"points":[[0.5,0.5]],"radius":0.03,"erases":false}"#.utf8)
        let stroke = try JSONDecoder().decode(LocalMask.BrushStroke.self, from: legacy)
        XCTAssertNil(stroke.softness)
        XCTAssertNil(stroke.strength)
    }

    func testEdgeBrushRestrictsPaintAndEraseAcrossAnOffCenterBoundary() throws {
        let dark = CIImage(color: CIColor(red: 0.16, green: 0.10, blue: 0.08))
            .cropped(to: CGRect(x: 0, y: 59, width: 160, height: 41))
        let light = CIImage(color: CIColor(red: 0.80, green: 0.82, blue: 0.77)).cropped(to: extent)
        let image = try engine.cgImage(dark.composited(over: light))
        for erases in [false, true] {
            let base = CIImage(color: erases ? .white : .black).cropped(to: extent)
            var mask = LocalMask(kind: .subject)
            mask.feather = 0
            mask.automaticPNG = try XCTUnwrap(engine.context.pngRepresentation(of: base, format: .L8,
                                                                              colorSpace: CGColorSpaceCreateDeviceGray()))
            var stroke = LocalMask.BrushStroke(points: [CGPoint(x: 0.40, y: 0.64), CGPoint(x: 0.62, y: 0.64)],
                                                radius: 0.09, erases: erases, softness: 0, strength: 50)
            mask.strokes = [stroke]
            let freehand = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(mask, extent: extent))
            XCTAssertEqual(sample(freehand, x: 80, y: 55), 128, accuracy: 3)

            stroke.edgeSelection = try BrushEdgeSelection.detect(in: image, stroke: stroke)
            mask.strokes = [stroke]
            mask = try JSONDecoder().decode(LocalMask.self, from: JSONEncoder().encode(mask))
            let guided = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(mask, extent: extent))
            XCTAssertEqual(sample(guided, x: 80, y: 64), 128, accuracy: 3)
            XCTAssertEqual(sample(guided, x: 80, y: 55), erases ? 255 : 0, accuracy: 3)
            XCTAssertEqual(sample(guided, x: 20, y: 64), erases ? 255 : 0, accuracy: 3)

            let overlay = CIImage(cgImage: try engine.automaticMaskOverlay(mask))
            let x = Int(overlay.extent.width * 0.5)
            let y = Int(overlay.extent.height * 0.55)
            XCTAssertEqual(sample(overlay, x: x, y: y, channel: 3), erases ? 122 : 0, accuracy: 3)
        }
    }

    func testHigherBrushSensitivityStopsAtASubtleColorBoundary() throws {
        let lighter = CIImage(color: CIColor(red: 0.39, green: 0.34, blue: 0.29)).cropped(to: extent)
        let darker = CIImage(color: CIColor(red: 0.35, green: 0.30, blue: 0.25))
            .cropped(to: CGRect(x: 0, y: 60, width: 160, height: 40))
        let image = try engine.cgImage(darker.composited(over: lighter))
        for erases in [false, true] {
            let base = CIImage(color: erases ? .white : .black).cropped(to: extent)
            var mask = LocalMask(kind: .subject)
            mask.feather = 0
            mask.automaticPNG = try XCTUnwrap(engine.context.pngRepresentation(
                of: base, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()))
            var stroke = LocalMask.BrushStroke(points: [CGPoint(x: 0.5, y: 0.65)],
                                                radius: 0.08, erases: erases, softness: 0)
            stroke.edgeSelection = try BrushEdgeSelection.detect(in: image, stroke: stroke, sensitivity: 25)
            mask.strokes = [stroke]
            let low = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(mask, extent: extent))
            stroke.edgeSelection = try BrushEdgeSelection.detect(in: image, stroke: stroke, sensitivity: 95)
            mask.strokes = [stroke]
            let high = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(mask, extent: extent))
            let editedValue = erases ? 0 : 255
            XCTAssertEqual(sample(low, x: 80, y: 55), editedValue, accuracy: 3)
            XCTAssertEqual(sample(high, x: 80, y: 55), 255 - editedValue, accuracy: 3)
            XCTAssertEqual(sample(high, x: 80, y: 65), editedValue, accuracy: 3)
        }
    }

    func testEdgePreviewMatchesTapsAndAnExtendedDrag() throws {
        let source = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 60))
            .composited(over: CIImage(color: .white).cropped(to: extent))
        let raster = try engine.cgImage(source)
        let halfSelection = CIImage(color: .white).cropped(to: CGRect(x: 80, y: 0, width: 80, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        var mask = LocalMask(kind: .subject)
        mask.feather = 0
        mask.automaticPNG = try XCTUnwrap(engine.context.pngRepresentation(
            of: halfSelection, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()))
        let coverage = try engine.edgeBrushCoverage(mask, imageSize: extent.size)

        let tap = [CGPoint(x: 0.5, y: 0.56)]
        let path = tap + [CGPoint(x: 0.40, y: 0.56), CGPoint(x: 0.29, y: 0.57)]
        for points in [tap, path] {
            try assertPreview(points)
        }

        func assertPreview(_ points: [CGPoint]) throws {
            let extended = points.count > 1
            for inverted in [false, true] {
                for erases in [false, true] {
                    var stroke = LocalMask.BrushStroke(points: points,
                        radius: 0.11, erases: erases, softness: 55, strength: 35)
                    let preview = try engine.edgeBrushPreview(in: raster, coverage: coverage, stroke: stroke,
                        sensitivity: 90, inverted: inverted)
                    let overlay = CIImage(cgImage: preview.image)
                    let full = CGRect(x: 0, y: 0, width: coverage.width, height: coverage.height)
                    let region = CGRect(x: preview.bounds.minX * full.width, y: preview.bounds.minY * full.height,
                                        width: preview.bounds.width * full.width, height: preview.bounds.height * full.height)
                    stroke.edgeSelection = try BrushEdgeSelection.detect(in: raster, stroke: stroke, sensitivity: 90)
                    mask.strokes = [stroke]
                    let after = try XCTUnwrap(LocalMaskRenderer.automaticCoverage(mask, extent: full))
                    let before = CIImage(cgImage: coverage, options: [.colorSpace: NSNull()])
                    var probes = [CGPoint(x: 0.46, y: 0.56), CGPoint(x: 0.54, y: 0.56),
                                  CGPoint(x: 0.46, y: 0.62), CGPoint(x: 0.54, y: 0.62)]
                    if extended {
                        probes += [CGPoint(x: 0.29, y: 0.57), CGPoint(x: 0.40, y: 0.56),
                                   CGPoint(x: 0.32, y: 0.62)]
                    }
                    for point in probes {
                        let x = Int(point.x * full.width), y = Int(point.y * full.height)
                        let difference = abs(sample(after, x: x, y: y) - sample(before, x: x, y: y))
                        let ox = x - Int(region.minX.rounded()), oy = y - Int(region.minY.rounded())
                        let alpha = sample(overlay, x: ox, y: oy, channel: 3)
                        XCTAssertEqual(alpha, Int(0.85 * sqrt(Double(difference) / 255) * 255), accuracy: 3)
                        if alpha > 0 {
                            let red = sample(overlay, x: ox, y: oy)
                            let blue = sample(overlay, x: ox, y: oy, channel: 2)
                            XCTAssertEqual(red > blue, erases != inverted)
                        }
                    }
                }
            }
        }
    }

    private func sample(_ image: CIImage, x: Int, y: Int, channel: Int = 0) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        engine.context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                              format: .RGBA8, colorSpace: engine.colorSpace)
        return Int(pixel[channel])
    }
}
