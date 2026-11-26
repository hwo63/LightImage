import CoreGraphics

public struct PortraitRetouch: Codable, Equatable, Sendable {
    public struct Settings: Codable, Equatable, Sendable {
        public var brighten = 0.0
        public var smoothing = 0.0
        public var slim = 0.0
        private var blemishAmount: Double?

        // Keep the automatic blemish correction from older edits until the
        // user chooses a separate value, including an explicit zero.
        public var blemishes: Double {
            get { blemishAmount ?? smoothing }
            set { blemishAmount = newValue }
        }

        var isEdited: Bool { brighten > 0 || smoothing > 0 || slim > 0 || blemishes > 0 }
    }

    private struct FaceEdit: Codable, Equatable, Sendable {
        let region: CGRect
        var settings: Settings
    }

    private var common = Settings()
    private var faces: [FaceEdit] = []

    var isEdited: Bool { common.isEdited || faces.contains { $0.settings.isEdited } }

    public func settings(for face: CGRect?) -> Settings {
        guard let face, let index = index(of: face) else { return common }
        return faces[index].settings
    }

    public func hasOwnSettings(for face: CGRect) -> Bool { index(of: face) != nil }

    mutating func update(for face: CGRect?, _ change: (inout Settings) -> Void) {
        if let face {
            var settings = settings(for: face)
            change(&settings)
            set(settings, for: face)
        } else {
            change(&common)
            for index in faces.indices { change(&faces[index].settings) }
            let shared = common
            faces.removeAll { $0.settings == shared }
        }
    }

    mutating func set(_ settings: Settings, for face: CGRect?) {
        guard let face else { common = settings; return }
        if let index = index(of: face) {
            faces[index] = FaceEdit(region: face, settings: settings)
        } else if settings != common {
            faces.append(FaceEdit(region: face, settings: settings))
        }
    }

    mutating func useCommonSettings(for face: CGRect) {
        if let index = index(of: face) { faces.remove(at: index) }
    }

    func settings(for subjects: [PortraitSubject]) -> [Settings] {
        var result = Array(repeating: common, count: subjects.count)
        var assigned: Set<Int> = []
        for edit in faces {
            let candidates = subjects.indices.filter { !assigned.contains($0) }
            guard let index = bestMatch(for: edit.region, in: candidates, region: { subjects[$0].face }) else { continue }
            result[index] = edit.settings
            assigned.insert(index)
        }
        return result
    }

    private func index(of face: CGRect) -> Int? {
        bestMatch(for: face, in: faces.indices, region: { faces[$0].region })
    }

    private func bestMatch<Indices: Sequence>(for face: CGRect, in indices: Indices,
                                             region: (Int) -> CGRect) -> Int? where Indices.Element == Int {
        var best: Int?
        var bestScore = 0.55
        for index in indices {
            let candidate = region(index)
            if candidate == face { return index }
            let overlap = face.intersection(candidate)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            let union = face.width * face.height + candidate.width * candidate.height - area
            guard union > 0 else { continue }
            let score = area / union
            if score > bestScore {
                bestScore = score
                best = index
            }
        }
        return best
    }
}
