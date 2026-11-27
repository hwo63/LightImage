import CryptoKit
import Foundation
import XCTest
import LightImageCore
@testable import LightImage

final class UpdateClientTests: XCTestCase {
    private let architecture = {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #endif
    }()

    @MainActor func testSettingsCheckReportsInlineWhileMenuCheckUsesAlert() {
        let updater = AppUpdater(client: nil)
        updater.checkManually(showAlert: false)
        XCTAssertEqual(updater.checkResult?.showAlert, false)
        XCTAssertEqual(updater.checkResult?.offersReleasePage, true)
        XCTAssertEqual(updater.checkResult?.detail.localized(.english),
                       "This build is missing update verification information. Download the official installer from GitHub.")
        updater.checkManually()
        XCTAssertEqual(updater.checkResult?.showAlert, true)
    }

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
        let archive = "LightImage-26.0.2-2611.080000-macOS-\(architecture).app.zip"
        let manifest = Data(#"{"version":"26.0.2","archive":"\#(archive)","size":10,"sha256":"fake"}"#.utf8)
        let responses = try fixtures(manifest: manifest, signer: untrustedKey)

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
        let archive = "LightImage-26.0.2-2611.080000-macOS-\(architecture).app.zip"
        let bytes = Data("wrong file".utf8)
        let manifest = Data(#"{"version":"26.0.2","archive":"\#(archive)","size":\#(bytes.count),"sha256":"fake"}"#.utf8)
        var responses = try fixtures(manifest: manifest, signer: key)
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

    func testLatestRedirectMustResolveToOfficialStableTag() async throws {
        FixtureURLProtocol.responses = ["latest": Data()]
        defer {
            FixtureURLProtocol.responses = [:]
            FixtureURLProtocol.latestURL = FixtureURLProtocol.officialLatestURL
        }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let client = UpdateClient(installedVersion: try XCTUnwrap(UpdateVersion("26.0.1")),
                                  publicKey: Curve25519.Signing.PrivateKey().publicKey,
                                  bundleID: "vn.hwo.LightImage", session: session)
        for url in ["https://github.com/hwo63/Other/releases/tag/v26.0.2",
                    "https://github.com/hwo63/LightImage/releases/tag/v26.0.2-beta"] {
            FixtureURLProtocol.latestURL = try XCTUnwrap(URL(string: url))
            do {
                _ = try await client.downloadLatest()
                XCTFail("Redirect must point to an official stable LightImage tag.")
            } catch {
                XCTAssertEqual(String(describing: error), "invalidRelease")
            }
        }
    }

    func testMissingSignedAssetsReportsAnError() async throws {
        FixtureURLProtocol.responses = ["latest": Data()]
        defer { FixtureURLProtocol.responses = [:] }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let client = UpdateClient(installedVersion: try XCTUnwrap(UpdateVersion("26.0.1")),
                                  publicKey: Curve25519.Signing.PrivateKey().publicKey,
                                  bundleID: "vn.hwo.LightImage", session: session)
        do {
            _ = try await client.downloadLatest()
            XCTFail("A newer release without signed assets must be reported as an error.")
        } catch {
            XCTAssertEqual(String(describing: error), "missingPackage")
        }
    }

    private func fixtures(manifest: Data, signer: Curve25519.Signing.PrivateKey) throws -> [String: Data] {
        let signature = try signer.signature(for: manifest).base64EncodedData()
        let name = "LightImage-update-\(architecture)"
        return ["latest": Data(), "\(name).json": manifest, "\(name).sig": signature]
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class FixtureURLProtocol: URLProtocol {
    static var responses: [String: Data] = [:]
    static let officialLatestURL = URL(string: "https://github.com/hwo63/LightImage/releases/tag/v26.0.2")!
    static var latestURL = officialLatestURL

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == "github.com",
              url != UpdateClient.latest || request.httpMethod == "HEAD" else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let body = Self.responses[url.lastPathComponent]
        let response = HTTPURLResponse(url: url == UpdateClient.latest ? Self.latestURL : url,
                                       statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body, !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
