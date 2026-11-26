import CryptoKit
import Foundation
import XCTest
@testable import LightImage

final class UpdateClientTests: XCTestCase {
    func testVersionComparisonIsNumericAndRejectsNonReleaseTags() throws {
        let installed = try XCTUnwrap(UpdateVersion("26.2.9"))
        XCTAssertGreaterThan(try XCTUnwrap(UpdateVersion("26.2.10")), installed)
        XCTAssertGreaterThan(try XCTUnwrap(UpdateVersion("27.0.0")), installed)
        XCTAssertEqual(try XCTUnwrap(UpdateVersion("06.0.1")).description, "06.0.1")
        for input in ["v26.0.1", "26.0.1-beta", "26.0.01", "26.0", "26.-1.1", "6.0.1", "26.0.1.0"] {
            XCTAssertNil(UpdateVersion(input), input)
        }
    }

    func testUnsignedManifestNeverStartsDownloadingTheArchive() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let untrustedKey = Curve25519.Signing.PrivateKey()
        let archive = "LightImage-26.0.2-2611.080000-macOS-arm64.app.zip"
        let manifest = Data(#"{"version":"26.0.2","archive":"\#(archive)","size":10,"sha256":"fake"}"#.utf8)
        let responses = try fixtures(manifest: manifest, signer: untrustedKey, archive: archive, size: 10)

        FixtureURLProtocol.responses = responses
        defer { FixtureURLProtocol.responses = [:] }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let client = UpdateClient(installedVersion: try XCTUnwrap(UpdateVersion("26.0.1")),
                                  publicKey: key.publicKey, bundleID: "vn.hwo.LightImage", session: session)

        do {
            _ = try await client.downloadLatest()
            XCTFail("An untrusted key cannot authorize an update.")
        } catch {
            XCTAssertEqual(String(describing: error), "invalidManifest")
        }

        FixtureURLProtocol.responses = ["latest": try XCTUnwrap(responses["latest"])]
        let current = UpdateClient(installedVersion: try XCTUnwrap(UpdateVersion("26.0.2")),
                                   publicKey: key.publicKey, bundleID: "vn.hwo.LightImage", session: session)
        let update = try await current.downloadLatest()
        XCTAssertNil(update)
        let alreadyStaged = try await client.downloadLatest(newerThan: UpdateVersion("26.0.2"))
        XCTAssertNil(alreadyStaged)
    }

    func testSignedManifestRejectsMismatchedArchiveBeforeExtraction() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let archive = "LightImage-26.0.2-2611.080000-macOS-arm64.app.zip"
        let bytes = Data("wrong file".utf8)
        let manifest = Data(#"{"version":"26.0.2","archive":"\#(archive)","size":\#(bytes.count),"sha256":"fake"}"#.utf8)
        var responses = try fixtures(manifest: manifest, signer: key, archive: archive, size: bytes.count)
        responses[archive] = bytes
        FixtureURLProtocol.responses = responses
        defer { FixtureURLProtocol.responses = [:] }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let client = UpdateClient(installedVersion: try XCTUnwrap(UpdateVersion("26.0.1")),
                                  publicKey: key.publicKey, bundleID: "vn.hwo.LightImage", session: session)

        do {
            _ = try await client.downloadLatest()
            XCTFail("A mismatched archive cannot be extracted.")
        } catch {
            XCTAssertEqual(String(describing: error), "invalidArchive")
        }
    }

    private func fixtures(manifest: Data, signer: Curve25519.Signing.PrivateKey, archive: String, size: Int) throws -> [String: Data] {
        let signature = try signer.signature(for: manifest).base64EncodedData()
        #if arch(arm64)
        let name = "LightImage-update-arm64"
        #elseif arch(x86_64)
        let name = "LightImage-update-x86_64"
        #endif
        let release = Data("""
        {"tag_name":"v26.0.2","draft":false,"prerelease":false,"assets":[
          {"name":"\(name).json","size":\(manifest.count)},
          {"name":"\(name).sig","size":\(signature.count)},
          {"name":"\(archive)","size":\(size)}
        ]}
        """.utf8)
        return ["latest": release, "\(name).json": manifest, "\(name).sig": signature]
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class FixtureURLProtocol: URLProtocol {
    static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let body = Self.responses[url.lastPathComponent] else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
