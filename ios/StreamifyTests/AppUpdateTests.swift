import Foundation
import XCTest
@testable import Streamify

final class AppUpdateTests: XCTestCase {
    func testAndroidDraftAndPrereleaseEntriesAreIgnored() throws {
        let entries = [release("android-v99"), release("ios-v9.0.0", draft: true),
                       release("ios-v8.0.0", prerelease: true), release("ios-v7.0.0-beta.1")]
        XCTAssertEqual(try evaluate(entries), .noRelease)
    }

    func testVersionsUseNumericComponentsAndIgnoreBuildMetadata() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppUpdateVersion("1.10.0")), try XCTUnwrap(AppUpdateVersion("1.9.9")))
        XCTAssertEqual(AppUpdateVersion("1.2.0+build.12"), AppUpdateVersion("1.2"))
        for value in ["", "1..0", "1.0.0.0", "1.0.0-rc.1", "01.2.3", "-1.2.3", "1.2.3+", "1.2.3+bad/path"] {
            XCTAssertNil(AppUpdateVersion(value), "Accepted invalid stable version \(value)")
        }
        let result = try evaluate([release("ios-v1.9.9"), release("ios-v1.10.0"), release("android-v500")], current: "1.9.9")
        guard case .available(let update) = result else { return XCTFail("Newer iOS release was not offered.") }
        XCTAssertEqual(update.version, "1.10.0")
        XCTAssertEqual(update.size, 4096)
        XCTAssertEqual(update.downloadURL.lastPathComponent, "Streamify.ipa")
    }

    func testInstalledOrOlderVersionIsNotOfferedAgain() throws {
        XCTAssertEqual(try evaluate([release("ios-v1.2.0")], current: "1.2.0"), .upToDate)
        XCTAssertEqual(try evaluate([release("ios-v1.1.0")], current: "1.2.0"), .upToDate)
        XCTAssertEqual(try evaluate([]), .noRelease)
    }

    func testUnsafeAssetURLsAndWrongReleasePathsAreRejected() throws {
        let prefix = "https://github.com/Joshua131313/Streamify/releases/download/ios-v2.0.0/"
        let unsafe = ["http://github.com/Joshua131313/Streamify/releases/download/ios-v2.0.0/Streamify.ipa",
                      "https://github.com.evil.test/Joshua131313/Streamify/releases/download/ios-v2.0.0/Streamify.ipa",
                      "https://github.com@evil.test/Joshua131313/Streamify/releases/download/ios-v2.0.0/Streamify.ipa",
                      "https://user@github.com/Joshua131313/Streamify/releases/download/ios-v2.0.0/Streamify.ipa",
                      "https://github.com/Other/Streamify/releases/download/ios-v2.0.0/Streamify.ipa",
                      "https://github.com/Joshua131313/Streamify/releases/download/ios-v3.0.0/Streamify.ipa",
                      prefix + "Streamify.ipa?redirect=evil", prefix + "Streamify.ipa#fragment",
                      prefix + "../Streamify.ipa", prefix + "%53treamify.ipa", prefix + "Streamify.apk",
                      "https://github.com:443/Joshua131313/Streamify/releases/download/ios-v2.0.0/Streamify.ipa"]
        for address in unsafe {
            XCTAssertThrowsError(try evaluate([release("ios-v2.0.0", assetURL: address)]), "Accepted unsafe address \(address)")
        }
        XCTAssertThrowsError(try evaluate([release("ios-v2.0.0", page: "https://github.com/Other/App/releases/tag/ios-v2.0.0")]))
        XCTAssertThrowsError(try evaluate([release("ios-v2.0.0", page: "https://github.com/Joshua131313/Streamify/releases/tag/ios-v3.0.0")]))
    }

    func testMissingOrInvalidAssetDoesNotClaimAUsableUpdate() throws {
        for size in [Int64(0), -1, AppUpdateClient.maximumIPABytes + 1] {
            XCTAssertThrowsError(try evaluate([release("ios-v2.0.0", size: size)]))
        }
        var noIPA = release("ios-v2.0.0")
        noIPA["assets"] = []
        XCTAssertThrowsError(try evaluate([noIPA]))
        XCTAssertThrowsError(try evaluate([release("ios-v2.0.0", assetName: "../Streamify.ipa")]))
        XCTAssertThrowsError(try evaluate([release("ios-v2.0.0", assetName: "Streamify..ipa")]))
    }

    func testNotesAreBoundedPlainTextAndMetadataIsSizeLimited() throws {
        var item = release("ios-v2.0.0")
        item["body"] = "# Fixes\n[Read](https://example.test)\u{0}" + String(repeating: "A", count: 3000)
        guard case .available(let update) = try evaluate([item]) else { return XCTFail("Missing update.") }
        XCTAssertEqual(update.notes.count, 2000)
        XCTAssertFalse(update.notes.contains("\u{0}"))
        XCTAssertTrue(update.notes.hasPrefix("# Fixes\n[Read](https://example.test)"))
        XCTAssertThrowsError(try AppUpdateClient.evaluate(data: Data(repeating: 32, count: AppUpdateClient.maximumResponseBytes + 1), currentVersion: "1.0.0"))
        XCTAssertThrowsError(try AppUpdateClient.evaluate(data: Data("{}".utf8), currentVersion: "1.0.0"))
        XCTAssertThrowsError(try evaluate(Array(repeating: release("ios-v2.0.0"), count: 31)))
    }

    func testClientRequestsOnlyPublicIOSReleaseMetadata() async throws {
        let fixture = UpdateFixture(.body(try data([release("android-v99"), release("ios-v2.0.0")])) )
        let update = try await AppUpdateClient(session: fixture.session).latest(currentVersion: "1.0.0")
        XCTAssertEqual(update?.version, "2.0.0")
        XCTAssertEqual(fixture.requests.count, 1)
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url, AppUpdateClient.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testClientRejectsLargeOrUnavailableResponses() async {
        let replies: [UpdateFixture.Reply] = [
            .body(Data("[]".utf8), status: 429),
            .body(Data("[]".utf8), status: 503),
            .body(Data("[]".utf8), headers: ["Content-Length": String(AppUpdateClient.maximumResponseBytes + 1)]),
            .body(Data(repeating: 32, count: AppUpdateClient.maximumResponseBytes + 1)),
            .body(Data("<html>maintenance</html>".utf8))
        ]
        for reply in replies {
            let fixture = UpdateFixture(reply)
            do { _ = try await AppUpdateClient(session: fixture.session).latest(currentVersion: "1.0.0"); XCTFail("Invalid response accepted.") }
            catch { XCTAssertTrue(error is AppUpdateError) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testClientCancellationAndOfflineAreDistinct() async {
        let offline = UpdateFixture(.failure(URLError(.notConnectedToInternet)))
        do { _ = try await AppUpdateClient(session: offline.session).latest(currentVersion: "1.0.0"); XCTFail("Offline request succeeded.") }
        catch { XCTAssertEqual((error as? AppUpdateError)?.localizedDescription, AppUpdateError.offline.localizedDescription) }

        let started = expectation(description: "Update request started")
        let pending = UpdateFixture(.pending(started))
        let task = Task { try await AppUpdateClient(session: pending.session).latest(currentVersion: "1.0.0") }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request succeeded.") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func evaluate(_ releases: [[String: Any]], current: String = "1.0.0") throws -> AppUpdateCheck {
        try AppUpdateClient.evaluate(data: data(releases), currentVersion: current)
    }
    private func data(_ releases: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: releases) }
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, assetURL: String? = nil,
                         page: String? = nil, size: Int64 = 4096, assetName: String = "Streamify.ipa") -> [String: Any] {
        ["tag_name": tag, "draft": draft, "prerelease": prerelease,
         "html_url": page ?? "https://github.com/Joshua131313/Streamify/releases/tag/\(tag)", "body": "Improvements and fixes.",
         "assets": [["name": assetName, "size": size,
                     "browser_download_url": assetURL ?? "https://github.com/Joshua131313/Streamify/releases/download/\(tag)/\(assetName)"]]]
    }
}

private final class UpdateFixture {
    enum Reply {
        case body(Data, status: Int = 200, headers: [String: String] = [:])
        case failure(URLError)
        case pending(XCTestExpectation)
    }
    let session: URLSession
    private let identifier = UUID().uuidString
    private let scenario: UpdateScenario
    var requests: [URLRequest] { scenario.requests }
    init(_ reply: Reply) {
        scenario = UpdateScenario(reply)
        UpdateURLProtocol.register(scenario, identifier: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Update-Test": identifier]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); UpdateURLProtocol.unregister(identifier) }
}

private final class UpdateScenario {
    private let lock = NSLock()
    let reply: UpdateFixture.Reply
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(_ reply: UpdateFixture.Reply) { self.reply = reply }
    func record(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; recorded.append(request) }
}

private final class UpdateURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: UpdateScenario] = [:]
    static func register(_ scenario: UpdateScenario, identifier: String) { lock.lock(); defer { lock.unlock() }; scenarios[identifier] = scenario }
    static func unregister(_ identifier: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: identifier) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-Streamify-Update-Test").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        guard let scenario, let url = request.url else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        scenario.record(request)
        switch scenario.reply {
        case .pending(let started): started.fulfill()
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .body(let data, let status, let headers):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
