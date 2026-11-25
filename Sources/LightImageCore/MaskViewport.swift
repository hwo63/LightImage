import CoreGraphics

/// Places an image in a clipped viewport and maps points to normalized
/// image coordinates, with the origin at bottom left.
public struct MaskViewport {
    private let viewport: CGSize
    private let image: CGSize
    private let fitScaleLimit: Double
    public let zoom: Double
    public let offset: CGSize

    public init(viewport: CGSize, image: CGSize, zoom: Double = 1, offset: CGSize = .zero,
                fitScaleLimit: Double = .infinity) {
        self.viewport = viewport
        self.image = image
        self.fitScaleLimit = fitScaleLimit
        self.zoom = min(max(zoom, 1), 8)
        let size = Self.fitted(image, in: viewport, fitScaleLimit: fitScaleLimit, zoom: self.zoom)
        let limitX = max(0, (size.width - viewport.width) / 2)
        let limitY = max(0, (size.height - viewport.height) / 2)
        self.offset = CGSize(width: min(max(offset.width, -limitX), limitX),
                             height: min(max(offset.height, -limitY), limitY))
    }

    public var frame: CGRect {
        let size = Self.fitted(image, in: viewport, fitScaleLimit: fitScaleLimit, zoom: zoom)
        return CGRect(x: (viewport.width - size.width) / 2 + offset.width,
                      y: (viewport.height - size.height) / 2 + offset.height,
                      width: size.width, height: size.height)
    }

    public func normalizedPoint(_ point: CGPoint) -> CGPoint {
        let rect = frame
        guard !rect.isEmpty else { return .zero }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: 1 - min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    public var normalizedCenter: CGPoint {
        normalizedPoint(CGPoint(x: viewport.width / 2, y: viewport.height / 2))
    }

    public func centered(on point: CGPoint) -> Self {
        let rect = frame
        return panned(by: CGSize(width: viewport.width / 2 - rect.minX - point.x * rect.width,
                                 height: viewport.height / 2 - rect.minY - (1 - point.y) * rect.height))
    }

    public func panned(by delta: CGSize) -> Self {
        Self(viewport: viewport, image: image, zoom: zoom,
             offset: CGSize(width: offset.width + delta.width, height: offset.height + delta.height),
             fitScaleLimit: fitScaleLimit)
    }

    public func magnified(to zoom: Double, around anchor: CGPoint) -> Self {
        let next = Self(viewport: viewport, image: image, zoom: zoom, fitScaleLimit: fitScaleLimit)
        let point = normalizedPoint(anchor)
        let rect = next.frame
        let position = CGPoint(x: rect.minX + point.x * rect.width,
                               y: rect.minY + (1 - point.y) * rect.height)
        return next.panned(by: CGSize(width: anchor.x - position.x, height: anchor.y - position.y))
    }

    private static func fitted(_ image: CGSize, in viewport: CGSize, fitScaleLimit: Double, zoom: Double) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(viewport.width / image.width, viewport.height / image.height, fitScaleLimit) * zoom
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
