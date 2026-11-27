import CoreImage
import CoreML
import CryptoKit
import Foundation

public struct ObjectRepair: Codable, Equatable, Sendable {
    public let region: CGRect
    public let png: Data

    public init(region: CGRect, png: Data) {
        self.region = region
        self.png = png
    }

    public static func composite(_ repairs: [Self], over source: CIImage) throws -> CIImage {
        try composite(repairs, over: source, adaptPatch: nil)
    }

    static func composite(_ repairs: [Self], over source: CIImage, adaptPatch: ((CIImage) -> CIImage)?) throws -> CIImage {
        try repairs.reduce(source) { image, repair in
            guard let patch = CIImage(data: repair.png), patch.extent.width > 0, patch.extent.height > 0,
                  repair.region.width > 0, repair.region.height > 0, !repair.region.isInfinite,
                  repair.region.intersects(CGRect(x: 0, y: 0, width: 1, height: 1)) else {
                throw LightImageError.exportFailed(tr("Không đọc được vùng ảnh đã lấp."))
            }
            let frame = image.extent
            let scaleX = repair.region.width * frame.width / patch.extent.width
            let scaleY = repair.region.height * frame.height / patch.extent.height
            let transform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY,
                tx: frame.minX + repair.region.minX * frame.width - patch.extent.minX * scaleX,
                ty: frame.minY + repair.region.minY * frame.height - patch.extent.minY * scaleY)
            return (adaptPatch?(patch) ?? patch).transformed(by: transform).composited(over: image).cropped(to: frame)
        }
    }
}

public actor GenerativeRemoval {
    private let modelDirectory: URL
    private let engine = ImageEngine()
    private var model: MLModel?
    private static let side = 800
    private static let revision = "201e8419315fdf26a822cfd1d15c94bc9d48d258"
    private static let assets = [
        ("Manifest.json", 617, "c814fff3cedf827c044094545ef80b0280b6cb8dd0e5c0bcf69fd31921191e58"),
        ("Data/com.apple.CoreML/model.mlmodel", 1_101_809, "06a100ef99e0fd16326a3a8c4a687d13f7b26f544ea906a75338932d8554f953"),
        ("Data/com.apple.CoreML/weights/weight.bin", 215_544_960, "d0541f6044a94cd4982bfdac074fc1ccfe11d8f1f590c299d6b5071b501fc184")
    ]

    public init(modelDirectory: URL) { self.modelDirectory = modelDirectory }

    public func repair(url: URL, repairs: [ObjectRepair], strokes: [LocalMask.BrushStroke]) async throws -> ObjectRepair {
        let source = try ObjectRepair.composite(repairs, over: engine.load(url: url, maxDimension: 3000))
        let extent = source.extent
        let longEdge = max(extent.width, extent.height)
        let area = strokes.reduce(CGRect.null) { area, stroke in
            let r = stroke.radius * longEdge
            return stroke.points.reduce(area) { area, point in
                area.union(CGRect(x: extent.minX + point.x * extent.width - r,
                                  y: extent.minY + point.y * extent.height - r, width: 2 * r, height: 2 * r))
            }
        }.intersection(extent)
        guard !area.isEmpty else { throw RemovalError.emptyMask }

        let width = max(max(area.width, area.height) * 1.8, min(240, longEdge))
        func origin(_ center: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            let proposed = center - width / 2
            return upper - lower >= width ? min(max(proposed, lower), upper - width) : (lower + upper - width) / 2
        }
        let x = origin(area.midX, min: extent.minX, max: extent.maxX)
        let y = origin(area.midY, min: extent.minY, max: extent.maxY)
        let scale = CGFloat(Self.side) / width
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: -x * scale, ty: -y * scale)
        let frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)

        let model = try await loadModel()
        try Task.checkCancellation()
        let input = try pixelBuffer(kCVPixelFormatType_32BGRA)
        let modelImage = source.clampedToExtent().transformed(by: transform).cropped(to: frame)
        engine.context.render(modelImage, to: input, bounds: frame, colorSpace: engine.colorSpace)
        let mask = try maskBuffer(strokes, extent: extent, transform: transform)
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: input), "mask": MLFeatureValue(pixelBuffer: mask)
        ])
        let prediction = try await model.prediction(from: features)
        guard let output = prediction.featureValue(for: "output")?.imageBufferValue else { throw RemovalError.invalidModel }

        let maskImage = CIImage(cvPixelBuffer: mask, options: [.colorSpace: NSNull()])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.85])
        let patchRect = area.applying(transform).insetBy(dx: -4, dy: -4).integral.intersection(frame)
        let transparent = CIImage(color: .clear).cropped(to: frame)
        let patch = CIImage(cvPixelBuffer: output, options: [.colorSpace: engine.colorSpace])
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: transparent, kCIInputMaskImageKey: maskImage
            ]).cropped(to: patchRect)
        guard let data = engine.context.pngRepresentation(of: patch, format: .RGBA8, colorSpace: engine.colorSpace) else {
            throw RemovalError.processing
        }
        let bounds = patchRect.applying(transform.inverted())
        return ObjectRepair(region: CGRect(x: (bounds.minX - extent.minX) / extent.width,
                                           y: (bounds.minY - extent.minY) / extent.height,
                                           width: bounds.width / extent.width, height: bounds.height / extent.height), png: data)
    }

    private func pixelBuffer(_ format: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Self.side, Self.side, format, attributes, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw RemovalError.processing }
        return buffer
    }

    private func maskBuffer(_ strokes: [LocalMask.BrushStroke], extent: CGRect, transform: CGAffineTransform) throws -> CVPixelBuffer {
        let buffer = try pixelBuffer(kCVPixelFormatType_OneComponent8)
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw RemovalError.processing }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Self.side, height: Self.side,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw RemovalError.processing }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setShouldAntialias(false)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let points = stroke.points.map { point in
                CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height).applying(transform)
            }
            guard let start = points.first else { continue }
            let radius = max(1, stroke.radius * max(extent.width, extent.height) * transform.a)
            if points.count == 1 {
                context.fillEllipse(in: CGRect(x: start.x - radius, y: start.y - radius, width: 2 * radius, height: 2 * radius))
            } else {
                context.setLineWidth(2 * radius)
                context.addLines(between: points)
                context.strokePath()
            }
        }
        return buffer
    }

    private func loadModel() async throws -> MLModel {
        if let model { return model }
        let files = FileManager.default
        let destination = modelDirectory.appendingPathComponent("LaMa-\(Self.revision).mlmodelc", isDirectory: true)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        if let cached = try? MLModel(contentsOf: destination, configuration: configuration) {
            model = cached
            return cached
        }
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }

        let staging = modelDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        let package = staging.appendingPathComponent("LaMa.mlpackage", isDirectory: true)
        for (path, size, hash) in Self.assets {
            try Task.checkCancellation()
            let url = URL(string: "https://huggingface.co/gumka/lama-coreml/resolve/\(Self.revision)/LaMa.mlpackage/\(path)")!
            let (temporary, response) = try await URLSession.shared.download(from: url)
            defer { try? files.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
                  try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize == size else { throw RemovalError.download }
            let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
            let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard checksum == hash else { throw RemovalError.invalidModel }
            let target = package.appendingPathComponent(path)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.moveItem(at: temporary, to: target)
        }
        let compiled = try await MLModel.compileModel(at: package)
        defer { try? files.removeItem(at: compiled) }
        do { try files.moveItem(at: compiled, to: destination) }
        catch { if !files.fileExists(atPath: destination.path) { throw error } }
        let loaded = try MLModel(contentsOf: destination, configuration: configuration)
        model = loaded
        return loaded
    }
}

private enum RemovalError: LocalizedError {
    case emptyMask, download, invalidModel, processing

    var errorDescription: String? {
        switch self {
        case .emptyMask: return tr("Hãy tô lên vật thể bạn muốn xóa.")
        case .download: return tr("Không tải được mô hình LaMa. Kiểm tra kết nối rồi thử lại.")
        case .invalidModel: return tr("Không xác minh được mô hình LaMa hoặc đầu ra của mô hình không hợp lệ.")
        case .processing: return tr("Không thể tạo và ghép vùng ảnh thay thế.")
        }
    }
}
