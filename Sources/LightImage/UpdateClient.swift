import CryptoKit
import Foundation

struct UpdateVersion: Comparable, CustomStringConvertible {
    private let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 3, numbers.count == 3, parts[0].utf8.count == 2,
              numbers.allSatisfy({ $0 >= 0 }),
              numbers[0] < 100,
              String(numbers[1]) == parts[1], String(numbers[2]) == parts[2],
              parts[0].utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        components = numbers
    }

    var description: String {
        String(format: "%02d", components[0]) + ".\(components[1]).\(components[2])"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct DownloadedUpdate {
    let version: UpdateVersion
    let directory: URL

    var app: URL { directory.appendingPathComponent("LightImage.app", isDirectory: true) }
}

struct UpdateClient {
    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let size: Int
        }
    }

    private struct Manifest: Decodable {
        let version: String
        let archive: String
        let size: Int
        let sha256: String
    }

    private enum Failure: Error {
        case invalidResponse, invalidManifest, invalidArchive, invalidBundle, toolExit(Int32)
    }

    private static let repository = "hwo63/LightImage"
    private static let latest = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    private static let downloadRoot = URL(string: "https://github.com/\(repository)/releases/download/")!
    private static let maximumArchiveBytes = 128 * 1024 * 1024

    private let session: URLSession
    private let installedVersion: UpdateVersion
    private let publicKey: Curve25519.Signing.PublicKey
    private let bundleID: String

    init?(bundle: Bundle = .main) {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let installedVersion = UpdateVersion(version),
              let key = bundle.object(forInfoDictionaryKey: "LightImageUpdatePublicKey") as? String,
              let bytes = Data(base64Encoded: key),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes),
              let bundleID = bundle.bundleIdentifier,
              bundle.url(forAuxiliaryExecutable: "LightImageInstaller") != nil else { return nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        self.init(installedVersion: installedVersion, publicKey: publicKey, bundleID: bundleID,
                  session: URLSession(configuration: configuration))
    }

    init(installedVersion: UpdateVersion, publicKey: Curve25519.Signing.PublicKey, bundleID: String, session: URLSession) {
        self.installedVersion = installedVersion
        self.publicKey = publicKey
        self.bundleID = bundleID
        self.session = session
    }

    func downloadLatest(newerThan stagedVersion: UpdateVersion? = nil) async throws -> DownloadedUpdate? {
        #if arch(arm64)
        let manifestName = "LightImage-update-arm64"
        #elseif arch(x86_64)
        let manifestName = "LightImage-update-x86_64"
        #endif

        var request = URLRequest(url: Self.latest, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (releaseBytes, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try Self.validate(response)
        let release = try JSONDecoder().decode(Release.self, from: releaseBytes)
        guard !release.draft, !release.prerelease, release.tag_name.hasPrefix("v"),
              let version = UpdateVersion(String(release.tag_name.dropFirst())),
              version > max(installedVersion, stagedVersion ?? installedVersion) else { return nil }

        let jsonName = "\(manifestName).json"
        let signatureName = "\(manifestName).sig"
        guard release.assets.contains(where: { $0.name == jsonName && (1...8192).contains($0.size) }),
              release.assets.contains(where: { $0.name == signatureName && (1...128).contains($0.size) })
        else { return nil }

        let releaseURL = Self.downloadRoot.appendingPathComponent(release.tag_name, isDirectory: true)
        async let json = assetBytes(jsonName, in: releaseURL, limit: 8192)
        async let signature = assetBytes(signatureName, in: releaseURL, limit: 128)
        let (manifestData, signatureData) = try await (json, signature)
        guard let signatureText = String(data: signatureData, encoding: .utf8),
              let detachedSignature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              publicKey.isValidSignature(detachedSignature, for: manifestData) else {
            throw Failure.invalidManifest
        }

        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.version == version.description,
              manifest.archive.range(of: #"\ALightImage-[A-Za-z0-9.\-]+\.app\.zip\z"#, options: .regularExpression) != nil,
              (1...Self.maximumArchiveBytes).contains(manifest.size),
              release.assets.contains(where: { $0.name == manifest.archive && $0.size == manifest.size }) else {
            throw Failure.invalidManifest
        }

        let (archive, downloadResponse) = try await session.download(from: releaseURL.appendingPathComponent(manifest.archive))
        defer { try? FileManager.default.removeItem(at: archive) }
        try Self.validate(downloadResponse)
        let archiveSize = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard archiveSize == manifest.size else { throw Failure.invalidArchive }
        let hash = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe))
        let checksum = hash.map { String(format: "%02x", $0) }.joined()
        guard checksum == manifest.sha256 else { throw Failure.invalidArchive }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightImage-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let update = DownloadedUpdate(version: version, directory: directory)
        do {
            try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
            let plist = update.app.appendingPathComponent("Contents/Info.plist")
            guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == bundleID,
                  info["CFBundleShortVersionString"] as? String == version.description,
                  info["LightImageUpdatePublicKey"] as? String == publicKey.rawRepresentation.base64EncodedString()
            else { throw Failure.invalidBundle }
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", update.app.path])
            return update
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func assetBytes(_ name: String, in root: URL, limit: Int) async throws -> Data {
        let (data, response) = try await session.data(from: root.appendingPathComponent(name))
        try Self.validate(response)
        guard !data.isEmpty, data.count <= limit else { throw Failure.invalidResponse }
        return data
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https" else {
            throw Failure.invalidResponse
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.toolExit(process.terminationStatus) }
    }
}
