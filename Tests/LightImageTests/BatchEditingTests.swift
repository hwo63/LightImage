import CoreImage
import XCTest
import LightImageCore
@testable import LightImage

@MainActor
final class BatchEditingTests: XCTestCase {
    func testPresetAppliesToCheckedPhotosAndEditedExportIgnoresTheFilter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = ImageEngine()
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 30, height: 20))
        let png = try XCTUnwrap(engine.context.pngRepresentation(of: image, format: .RGBA8, colorSpace: engine.colorSpace))
        let records = try ["first", "second", "excluded", "already-edited"].map { name in
            let url = directory.appendingPathComponent(name).appendingPathExtension("png")
            try png.write(to: url)
            return PhotoRecord(path: url.path)
        }
        let model = AppModel(dataDirectory: directory)
        model.catalog.photos = records
        model.catalog.photos[0].adjustments.cropAspect = 1
        model.catalog.photos[3].adjustments[PhotoEnhancement.restore.key] = 50
        model.select(records[2].id)
        model.setBatchSelection(records[0].id, included: true)
        model.setBatchSelection(records[1].id, included: true)
        model.query = "second"

        var settings = Adjustments()
        settings["Exposure2012"] = 0.5
        model.apply(PhotoPreset(name: "Batch exposure", settings: settings))
        XCTAssertEqual(model.catalog.photos.map { $0.adjustments["Exposure2012"] }, [0.5, 0.5, 0, 0])
        XCTAssertEqual(model.catalog.photos[0].adjustments.cropAspect, 1)
        XCTAssertEqual(model.selectedID, records[0].id)
        XCTAssertEqual(model.exportTargets(.selected).map(\.id), [records[0].id, records[1].id])
        XCTAssertEqual(model.exportTargets(.filtered).map(\.id), [records[1].id])
        XCTAssertEqual(model.exportTargets(.edited).map(\.id), [records[0].id, records[1].id, records[3].id])

        model.undo()
        XCTAssertEqual(model.edits["Exposure2012"], 0)
        XCTAssertEqual(model.catalog.photos[1].adjustments["Exposure2012"], 0.5)
    }
}
