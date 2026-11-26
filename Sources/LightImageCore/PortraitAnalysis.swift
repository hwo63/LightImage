import CoreGraphics
import Vision

public struct PortraitSubject: Sendable {
    public let face: CGRect
    public let eyes: [CGRect]
    public let lips: CGRect?
    public var waist: PortraitWaist?
    var nose: CGRect? = nil
    var arms: [PortraitLimb] = []
    var legs: [PortraitLimb] = []

    public var canSlimArms: Bool { !arms.isEmpty }
    public var canSlimLegs: Bool { !legs.isEmpty }

    public func matches(_ selection: CGRect) -> Bool {
        let overlap = face.intersection(selection)
        return !overlap.isNull && overlap.width * overlap.height > face.width * face.height * 0.45
    }
}

struct PortraitLimb: Sendable {
    let start: CGPoint
    let end: CGPoint
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
                return PortraitSubject(face: box, eyes: eyes, lips: bounds(landmarks?.outerLips), waist: nil,
                                       nose: bounds(landmarks?.nose))
            }
            .sorted { $0.face.midX < $1.face.midX }

        if !subjects.isEmpty {
            let poses = VNDetectHumanBodyPoseRequest()
            // A pose failure must not prevent the face controls from working.
            if (try? handler.perform([poses])) != nil {
                let aspect = Double(image.height) / Double(image.width)
                for pose in poses.results ?? [] {
                    guard let points = try? pose.recognizedPoints(.all),
                          let nose = points[.nose], nose.confidence >= 0.45 else { continue }
                    let head = nose.location
                    let matches = subjects.indices.filter { subjects[$0].face.contains(head) }
                    guard matches.count == 1, let index = matches.first else { continue }
                    subjects[index].waist = waist(in: points, head: head, aspect: aspect)
                    subjects[index].arms = limbs(in: points, chains: [
                        [.leftShoulder, .leftElbow, .leftWrist], [.rightShoulder, .rightElbow, .rightWrist]
                    ])
                    subjects[index].legs = limbs(in: points, chains: [
                        [.leftHip, .leftKnee, .leftAnkle], [.rightHip, .rightKnee, .rightAnkle]
                    ])
                }
            }
        }
        return Self(subjects: subjects)
    }

    private typealias Joint = VNHumanBodyPoseObservation.JointName

    private static func limbs(in points: [Joint: VNRecognizedPoint], chains: [[Joint]]) -> [PortraitLimb] {
        chains.flatMap { joints in
            zip(joints, joints.dropFirst()).compactMap { start, end in
                guard let a = points[start], let b = points[end], a.confidence >= 0.55, b.confidence >= 0.55,
                      a.location != b.location else { return nil }
                return PortraitLimb(start: a.location, end: b.location)
            }
        }
    }

    private static func waist(in points: [Joint: VNRecognizedPoint], head: CGPoint, aspect: Double) -> PortraitWaist? {
        func point(_ key: Joint) -> CGPoint? {
            guard let point = points[key], point.confidence >= 0.45 else { return nil }
            return point.location
        }
        guard let leftHip = point(.leftHip), let rightHip = point(.rightHip),
              let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder) else { return nil }

        let hips = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let shoulders = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)
        let hipWidth = hypot(leftHip.x - rightHip.x, (leftHip.y - rightHip.y) * aspect)
        let torso = hypot(shoulders.x - hips.x, (shoulders.y - hips.y) * aspect)
        guard hipWidth > 0.015, torso > hipWidth * 0.75, head.y > shoulders.y, shoulders.y > hips.y else { return nil }

        let center = CGPoint(x: hips.x + (shoulders.x - hips.x) * 0.30, y: hips.y + (shoulders.y - hips.y) * 0.30)
        let angle = atan2(hips.x - shoulders.x, (shoulders.y - hips.y) * aspect)
        return PortraitWaist(center: center, width: min(hipWidth * 2.15, torso * 1.6), angle: angle)
    }
}
