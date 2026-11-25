import CoreGraphics
import Vision

public struct PortraitSubject: Sendable {
    public let face: CGRect
    public let eyes: [CGRect]
    public let lips: CGRect?
    public var waist: PortraitWaist?

    public func matches(_ selection: CGRect) -> Bool {
        let overlap = face.intersection(selection)
        return !overlap.isNull && overlap.width * overlap.height > face.width * face.height * 0.45
    }
}

public struct PortraitWaist: Codable, Equatable, Sendable {
    public var center: CGPoint
    public var width: Double
    public var angle: Double

    public init(center: CGPoint, width: Double, angle: Double = 0) {
        self.center = center
        self.width = width
        self.angle = angle
    }
}

public struct PortraitAnalysis: Sendable {
    public let subjects: [PortraitSubject]

    public func targets(_ selection: CGRect?) -> [PortraitSubject] {
        guard let selection else { return subjects }
        return Array(subjects.filter { $0.matches(selection) }.prefix(1))
    }

    static func analyze(_ image: CGImage) throws -> Self {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let faces = VNDetectFaceLandmarksRequest()
        try handler.perform([faces])
        var subjects = (faces.results ?? []).filter { $0.boundingBox.width > 0 && $0.boundingBox.height > 0 }
            .map { observation in
                let box = observation.boundingBox
                let landmarks = observation.landmarks
                func bounds(_ region: VNFaceLandmarkRegion2D?) -> CGRect? {
                    guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
                    let xs = points.map { box.minX + $0.x * box.width }
                    let ys = points.map { box.minY + $0.y * box.height }
                    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                }
                let eyeRegions = [landmarks?.leftEye, landmarks?.rightEye]
                let browRegions = [landmarks?.leftEyebrow, landmarks?.rightEyebrow]
                let eyes = zip(eyeRegions, browRegions).compactMap { eye, brow -> CGRect? in
                    guard let eye = bounds(eye) else { return nil }
                    return bounds(brow).map { eye.union($0) } ?? eye
                }
                return PortraitSubject(face: box, eyes: eyes, lips: bounds(landmarks?.outerLips), waist: nil)
            }
            .sorted { $0.face.midX < $1.face.midX }

        if !subjects.isEmpty {
            let poses = VNDetectHumanBodyPoseRequest()
            // A pose failure must not prevent the face controls from working.
            if (try? handler.perform([poses])) != nil {
                let aspect = Double(image.height) / Double(image.width)
                for pose in poses.results ?? [] {
                    guard let (head, waist) = waist(in: pose, aspect: aspect) else { continue }
                    let matches = subjects.indices.filter { subjects[$0].face.contains(head) }
                    guard matches.count == 1, let index = matches.first else { continue }
                    subjects[index].waist = waist
                }
            }
        }
        return Self(subjects: subjects)
    }

    private static func waist(in pose: VNHumanBodyPoseObservation, aspect: Double) -> (CGPoint, PortraitWaist)? {
        func point(_ key: VNHumanBodyPoseObservation.JointName, confidence: Float = 0.45) -> CGPoint? {
            guard let point = try? pose.recognizedPoint(key), point.confidence >= confidence else { return nil }
            return point.location
        }
        guard let head = point(.nose), let leftHip = point(.leftHip), let rightHip = point(.rightHip),
              let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder) else { return nil }

        let hips = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let shoulders = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)
        let hipWidth = hypot(leftHip.x - rightHip.x, (leftHip.y - rightHip.y) * aspect)
        let torso = hypot(shoulders.x - hips.x, (shoulders.y - hips.y) * aspect)
        guard hipWidth > 0.015, torso > hipWidth * 0.75, head.y > shoulders.y, shoulders.y > hips.y else { return nil }

        let center = CGPoint(x: hips.x + (shoulders.x - hips.x) * 0.30, y: hips.y + (shoulders.y - hips.y) * 0.30)
        let angle = atan2(hips.x - shoulders.x, (shoulders.y - hips.y) * aspect)
        return (head, PortraitWaist(center: center, width: min(hipWidth * 2.15, torso * 1.6), angle: angle))
    }
}
