import CryptoKit
import Darwin
import Foundation

private enum SignError: LocalizedError {
    case usage, key, archive

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
            Usage:
              swift scripts/sign-update.swift --create-key /path/to/private-key
              swift scripts/sign-update.swift --public-key
              swift scripts/sign-update.swift VERSION ARCH ARCHIVE.app.zip OUTPUT_DIRECTORY
            Supply LIGHTIMAGE_UPDATE_PRIVATE_KEY to derive the public key or sign an archive.
            """
        case .key:
            return "LIGHTIMAGE_UPDATE_PRIVATE_KEY must contain a base64-encoded Ed25519 private key."
        case .archive:
            return "Invalid version, architecture, or LightImage update archive."
        }
    }
}

private struct Manifest: Encodable {
    let version: String
    let archive: String
    let size: Int
    let sha256: String
}

private func createKey(at path: String) throws {
    let key = Curve25519.Signing.PrivateKey()
    // Create exclusively with owner-only permissions before writing any key material.
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try file.write(contentsOf: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8))
    try file.close()
    print(key.publicKey.rawRepresentation.base64EncodedString())
}

private func privateKey() throws -> Curve25519.Signing.PrivateKey {
    guard let value = ProcessInfo.processInfo.environment["LIGHTIMAGE_UPDATE_PRIVATE_KEY"],
          let bytes = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: bytes) else { throw SignError.key }
    return key
}

private func run(_ args: [String]) throws {
    if args.count == 2, args[0] == "--create-key" {
        try createKey(at: args[1])
        return
    }
    if args == ["--public-key"] {
        print(try privateKey().publicKey.rawRepresentation.base64EncodedString())
        return
    }

    guard args.count == 4 else { throw SignError.usage }
    let version = args[0]
    let architecture = args[1]
    let archive = URL(fileURLWithPath: args[2])
    let directory = URL(fileURLWithPath: args[3], isDirectory: true)
    guard version.range(of: #"\A[0-9]{2}\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z"#, options: .regularExpression) != nil,
          ["arm64", "x86_64"].contains(architecture),
          archive.lastPathComponent.hasPrefix("LightImage-\(version)-"),
          archive.lastPathComponent.hasSuffix("-macOS-\(architecture).app.zip"),
          let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          (1...(128 * 1024 * 1024)).contains(size) else { throw SignError.archive }

    let hash = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe))
    let checksum = hash.map { String(format: "%02x", $0) }.joined()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(Manifest(version: version, archive: archive.lastPathComponent, size: size, sha256: checksum))
    let signature = try privateKey().signature(for: data)
    let name = "LightImage-update-\(architecture)"
    try data.write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
    try Data((signature.base64EncodedString() + "\n").utf8)
        .write(to: directory.appendingPathComponent("\(name).sig"), options: .atomic)
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
