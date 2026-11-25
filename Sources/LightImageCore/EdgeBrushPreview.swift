import CoreImage

public struct EdgeBrushPreview: Sendable {
    public let image: CGImage
    /// Normalized image coordinates, with the origin at bottom left.
    public let bounds: CGRect
}

extension ImageEngine {
    /// Snapshot the current selection once, even when the pink guide is hidden.
    public func edgeBrushCoverage(_ mask: LocalMask, imageSize: CGSize) throws -> CGImage {
        let scale = 2048 / max(imageSize.width, imageSize.height)
        let extent = CGRect(x: 0, y: 0, width: (imageSize.width * scale).rounded(),
                            height: (imageSize.height * scale).rounded())
        guard let coverage = LocalMaskRenderer.automaticCoverage(mask, extent: extent),
              let image = context.createCGImage(coverage, from: extent, format: .L8,
                                                colorSpace: CGColorSpaceCreateDeviceGray()) else {
            throw AutomaticMaskError.unavailable
        }
        return image
    }

    public func edgeBrushPreview(in source: CGImage, coverage: CGImage, stroke: LocalMask.BrushStroke,
                                 sensitivity: Double, inverted: Bool) throws -> EdgeBrushPreview {
        var stroke = stroke
        let edge = try BrushEdgeSelection.detect(in: source, stroke: stroke, sensitivity: sensitivity)
        stroke.edgeSelection = edge
        let extent = CGRect(x: 0, y: 0, width: coverage.width, height: coverage.height)
        let bounds = edge.bounds
        let region = CGRect(x: bounds.minX * extent.width, y: bounds.minY * extent.height,
                            width: bounds.width * extent.width, height: bounds.height * extent.height)
            .integral.intersection(extent)
        let selected = CIImage(cgImage: coverage, options: [.colorSpace: NSNull()])
        let isErasing = stroke.erases != inverted
        let tint = isErasing ? CIVector(x: 1, y: 0.63, z: 0.16) : CIVector(x: 0.19, y: 0.92, z: 0.82)
        guard let brush = LocalMaskRenderer.brushPreview(stroke, extent: extent, region: region),
              let output = Self.brushPreviewKernel?.apply(extent: region, arguments: [
                  brush, selected, tint, stroke.erases ? 1.0 : 0.0
              ]) else { throw AutomaticMaskError.unavailable }
        return EdgeBrushPreview(image: try cgImage(output),
            bounds: CGRect(x: region.minX / extent.width, y: region.minY / extent.height,
                           width: region.width / extent.width, height: region.height / extent.height))
    }

    private static let brushPreviewKernel = CIColorKernel(source: """
        kernel vec4 edgeBrushPreview(__sample brush, __sample mask, vec3 tint, float erase) {
            float change = brush.a * mix(1.0 - mask.r, mask.r, erase);
            float alpha = 0.85 * sqrt(clamp(change, 0.0, 1.0));
            return vec4(tint * alpha, alpha);
        }
        """)
}
