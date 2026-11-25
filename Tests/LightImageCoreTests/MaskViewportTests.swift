import CoreGraphics
import XCTest
@testable import LightImageCore

final class MaskViewportTests: XCTestCase {
    func testZoomedPhotoKeepsItsCenterWhenComparisonPanelSizeChanges() {
        let image = CGSize(width: 2400, height: 1600)
        let location = CGPoint(x: 0.65, y: 0.4)
        let single = MaskViewport(viewport: CGSize(width: 840, height: 520), image: image, zoom: 4)
            .centered(on: location)
        let comparison = MaskViewport(viewport: CGSize(width: 412, height: 494), image: image, zoom: single.zoom)
            .centered(on: single.normalizedCenter)

        XCTAssertEqual(comparison.normalizedCenter.x, location.x, accuracy: 1e-9)
        XCTAssertEqual(comparison.normalizedCenter.y, location.y, accuracy: 1e-9)
    }

    func testPreviewFitDoesNotUpscaleSmallImagesAndAllowsWheelZoom() {
        let viewport = CGSize(width: 600, height: 400)
        let image = CGSize(width: 200, height: 100)
        let fitted = MaskViewport(viewport: viewport, image: image, fitScaleLimit: 1)
        XCTAssertEqual(fitted.frame.size, image)

        let center = CGPoint(x: 300, y: 200)
        let enlarged = fitted.magnified(to: 2, around: center)
        XCTAssertEqual(enlarged.frame.size, CGSize(width: 400, height: 200))
        XCTAssertEqual(enlarged.magnified(to: 0.5, around: center).frame, fitted.frame)
    }

    func testBrushCoordinatesStayAttachedThroughZoomAndPan() {
        let fitted = MaskViewport(viewport: CGSize(width: 600, height: 520), image: CGSize(width: 2400, height: 1600))
        let point = CGPoint(x: 380, y: 220)
        XCTAssertEqual(fitted.frame.minY, 60, accuracy: 1e-9)
        let brush = fitted.normalizedPoint(point)

        let enlarged = fitted.magnified(to: 3.5, around: point)
        let zoomedBrush = enlarged.normalizedPoint(point)
        XCTAssertEqual(zoomedBrush.x, brush.x, accuracy: 1e-9)
        XCTAssertEqual(zoomedBrush.y, brush.y, accuracy: 1e-9)

        let delta = CGSize(width: -95, height: 63)
        let moved = enlarged.panned(by: delta)
        let movedBrush = moved.normalizedPoint(CGPoint(x: point.x + delta.width, y: point.y + delta.height))
        XCTAssertEqual(movedBrush.x, brush.x, accuracy: 1e-9)
        XCTAssertEqual(movedBrush.y, brush.y, accuracy: 1e-9)
    }

    func testPanReachesTheImageEdgesAndResetsAtFit() {
        let viewport = CGSize(width: 600, height: 420)
        let portrait = CGSize(width: 1600, height: 2400)
        let enlarged = MaskViewport(viewport: viewport, image: portrait, zoom: 8)
        let moved = enlarged.panned(by: CGSize(width: 10000, height: -10000))
        XCTAssertEqual(moved.frame.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(moved.frame.maxY, viewport.height, accuracy: 1e-9)
        XCTAssertEqual(moved.normalizedPoint(CGPoint(x: 0, y: viewport.height)), .zero)
        let fitted = moved.magnified(to: 1, around: CGPoint(x: 0, y: viewport.height))
        XCTAssertEqual(fitted.offset, .zero)
        XCTAssertEqual(fitted.frame.midX, viewport.width / 2)
        XCTAssertEqual(fitted.frame.midY, viewport.height / 2)
    }
}
