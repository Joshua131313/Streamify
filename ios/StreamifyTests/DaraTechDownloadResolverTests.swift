import Foundation
import XCTest
@testable import Streamify

/// Every response is local. Search/download fixtures retain the actual public
/// FROM and Inception response shapes; no API key or provider request is used.
final class DaraTechDownloadResolverTests: XCTestCase {
    private let key = "caller-owned-fixture-key"
    private let from = MediaItem(id: 124364, kind: .tv, title: "FROM", releaseDate: "2022-02-20")
    private let inception = MediaItem(id: 27205, kind: .movie, title: "Inception", releaseDate: "2010-07-15")

    func testFROMUsesExactIdentityEpisodeAndActualReturned1080FileWithoutMediaAuthorization() async throws {
        let fixture = DaraTechFixture([
            .json(search([fromIdentity, identity(id: "6166617723586970976", title: "From", year: 2024, type: 6)])),
            .json(downloads([fromFile(), file("https://cdn.example.test/480.mp4", quality: 480)])),
            .video(Self.movie(width: 1920, height: 1080))
        ])
        let checked = DaraTechNativeChecks()
        let result = try await DaraTechDownloadResolver(session: fixture.session,
            validateNativeSource: { await checked.record($0) })
            .resolve(media: from, apiKey: key)
        XCTAssertEqual(result.url.absoluteString, fromURL())
        XCTAssertEqual(result.quality, 1080)
        XCTAssertEqual(result.sourceID, "DaraTech")
        XCTAssertEqual(result.actualWidth, 1920)
        XCTAssertEqual(result.actualHeight, 1080)
        XCTAssertEqual(result.actualCodecs, ["avc1"])
        XCTAssertEqual(result.headers, [:])
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "q", value: "FROM")])
        XCTAssertEqual(requests[1].url?.path, "/v1/tvshows/267563007482495928/season/1/episode/1/download")
        for request in requests.prefix(2) {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
        // The returned media currently uses the SAME host as metadata. It must
        // still receive no key, not just rely on cross-host header stripping.
        XCTAssertEqual(requests[2].url?.host, requests[0].url?.host)
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Range"), "bytes=0-65535")
        XCTAssertTrue(requests.allSatisfy { $0.url?.absoluteString.contains(key) == false })
        let native = await checked.urls
        XCTAssertEqual(native, [result.url])
    }

    func testInceptionUsesMovieIdentityAndLiteralReturnedFileInsteadOfTVDefaults() async throws {
        let address = "https://apimovie.runflix.name.ng/v1/media/download/6391474290696802080/1080?se=0&ep=0"
        let fixture = DaraTechFixture([
            .json(search([identity(id: "6391474290696802080", title: "Inception", year: 2010, type: 2)])),
            .json(downloads([file(address, size: 2_414_667_149)])), .video(Self.movie(width: 1920, height: 1080))
        ])
        let result = try await resolver(fixture).resolve(media: inception, apiKey: key, season: 8, episode: 9)
        XCTAssertEqual(result.url.absoluteString, address)
        XCTAssertEqual(result.actualWidth, 1920)
        XCTAssertEqual(fixture.requests[1].url?.path, "/v1/movies/6391474290696802080/download")
        XCTAssertNil(fixture.requests[1].url?.query)
    }

    func testFreshRequestsKeepEpisodeAndCallerKeyIndependentOnEachResolution() async throws {
        let fixture = DaraTechFixture([
            .json(search([fromIdentity])), .json(downloads([fromFile()])), .video(Self.movie(width: 1920, height: 1080)),
            .json(search([fromIdentity])), .json(downloads([fromFile(episode: 2)])), .video(Self.movie(width: 1920, height: 1080))
        ])
        let adapter = resolver(fixture)
        let first = try await adapter.resolve(media: from, apiKey: key)
        let second = try await adapter.resolve(media: from, apiKey: "another-caller-fixture-key", season: 1, episode: 2)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(second.url.absoluteString, fromURL(episode: 2))
        XCTAssertEqual(fixture.requests.count, 6)
        XCTAssertEqual(fixture.requests[4].url?.path, "/v1/tvshows/267563007482495928/season/1/episode/2/download")
        XCTAssertEqual(fixture.requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer another-caller-fixture-key")
        XCTAssertNil(fixture.requests[5].value(forHTTPHeaderField: "Authorization"))
    }

    func testMissing720NeverProbes1080Or480OrConstructsADownloadURL() async {
        let fixture = DaraTechFixture([.json(search([fromIdentity])),
            .json(downloads([fromFile(), file("https://cdn.example.test/480.mp4", quality: 480)]))])
        do { _ = try await resolver(fixture).resolve(media: from, apiKey: key, quality: 720); XCTFail("Missing exact quality must fail") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .qualityUnavailable) }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testIdentityRequiresExactTitleYearTypeAndAnyExplicitTMDBIdentifier() async {
        var mismatchedTMDB = fromIdentity
        mismatchedTMDB["externalIds"] = ["tmdb": 999]
        var inconsistentYear = fromIdentity
        inconsistentYear["releaseDate"] = "2024-02-20"
        var inconsistentSubject = fromIdentity
        inconsistentSubject["subjectId"] = "999"
        let wrong: [[String: Any]] = [
            identity(id: "1", title: "From Now", year: 2022, type: 1),
            identity(id: "2", title: "FROM", year: 2024, type: 1),
            identity(id: "3", title: "FROM", year: 2022, type: 2),
            identity(id: "../private", title: "FROM", year: 2022, type: 1),
            mismatchedTMDB, inconsistentYear, inconsistentSubject
        ]
        for item in wrong {
            let fixture = DaraTechFixture([.json(search([item]))])
            do { _ = try await resolver(fixture).resolve(media: from, apiKey: key); XCTFail("An unverified identity was accepted") }
            catch { XCTAssertEqual(error as? DaraTechDownloadError, .identityUnavailable) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testDuplicateRowsForOneIdentityAreDeduplicatedButDifferentSubjectsAreAmbiguous() async throws {
        var verified = fromIdentity
        verified["externalIds"] = ["tmdb": "124364"]
        let duplicate = DaraTechFixture([.json(search([verified, verified])), .json(downloads([fromFile()])),
                                        .video(Self.movie(width: 1920, height: 1080))])
        _ = try await resolver(duplicate).resolve(media: from, apiKey: key)
        let ambiguous = DaraTechFixture([.json(search([fromIdentity, identity(id: "123", title: "From", year: 2022, type: 1)]))])
        do { _ = try await resolver(ambiguous).resolve(media: from, apiKey: key); XCTFail("Ambiguous title must not pick the first row") }
        catch { XCTAssertEqual(error as? DaraTechDownloadError, .ambiguousIdentity) }
        XCTAssertEqual(ambiguous.requests.count, 1)
    }

    func testUnsafeDRMMemberOnlyPlaylistAndWrongEpisodeLinksNeverReachMedia() async {
        var drm = fromFile(); drm["licenseUrl"] = "https://license.example.test/"
        var membership = fromFile(); membership["requireMemberType"] = 1
        var label = fromFile(); label["quality"] = "480p SD"
        var oversized = fromFile(); oversized["size"] = 80 * 1024 * 1024 * 1024; oversized["sizeBytes"] = oversized["size"]
        var disagreeingSize = fromFile(); disagreeingSize["size"] = 1
        let links = [
            file("http://cdn.example.test/video.mp4"),
            file("https://user:password@cdn.example.test/video.mp4"),
            file("https://cdn.example.test:8443/video.mp4"),
            file("https://cdn.example.test/video.mp4#fragment"),
            file("https://cdn.example.test/master.m3u8"),
            file("https://cdn.example.test/player.html"),
            file("https://cdn.example.test/file.mp4?apikey=private"),
            file(fromURL(episode: 2)), drm, membership, label, oversized, disagreeingSize
        ]
        for link in links {
            let fixture = DaraTechFixture([.json(search([fromIdentity])), .json(downloads([link]))])
            do { _ = try await resolver(fixture).resolve(media: from, apiKey: key); XCTFail("Unsafe or wrong-episode source was accepted") }
            catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .unsafeSource) }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    func testMislabeledDimensionsCanOnlyTryAnotherActuallyReturnedExactTier() async throws {
        let low = "https://cdn.example.test/mislabeled.mp4", correct = "https://cdn.example.test/actual.mp4"
        let fixture = DaraTechFixture([.json(search([fromIdentity])),
            .json(downloads([file(low), file(correct), file("https://cdn.example.test/unselected.mp4", quality: 480)])),
            .video(Self.movie(width: 854, height: 480)), .video(Self.movie(width: 1920, height: 804))])
        let result = try await resolver(fixture).resolve(media: from, apiKey: key)
        XCTAssertEqual(result.url.absoluteString, correct)
        XCTAssertEqual(result.actualHeight, 804)
        XCTAssertEqual(result.quality, 1080)
        XCTAssertEqual(fixture.requests.count, 4)
        XCTAssertFalse(fixture.requests.contains { $0.url?.lastPathComponent == "unselected.mp4" })
    }

    func testMetadata429PreservesStatusAndRetryAfterWithoutRetryingOrUsingAnotherCredential() async {
        let fixture = DaraTechFixture([.body(Data(), status: 429, headers: ["Retry-After": "120"])])
        do { _ = try await resolver(fixture).resolve(media: from, apiKey: key); XCTFail("Rate limit must remain an error") }
        catch { XCTAssertEqual(error as? DaraTechDownloadError, .http(status: 429, retryAfter: "120")) }
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertEqual(fixture.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
    }

    func testMedia429StopsTheExactQualityCandidateLoop() async {
        let fixture = DaraTechFixture([.json(search([fromIdentity])),
            .json(downloads([file("https://cdn.example.test/busy.mp4"), file("https://cdn.example.test/second.mp4")])),
            .body(Data(), status: 429, headers: ["Retry-After": "60"])])
        do { _ = try await resolver(fixture).resolve(media: from, apiKey: key); XCTFail("Source rate limit must stop") }
        catch let error as DownloadSourceProbeError {
            guard case .rejected(429) = error else { XCTFail("The source429 must not become a codec error"); return }
        } catch { XCTFail("Expected source HTTP429") }
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertNil(fixture.requests.last?.value(forHTTPHeaderField: "Authorization"))
    }

    func testMetadataRedirectCannotForwardTheCallerKeyToAnotherOrigin() async {
        let fixture = DaraTechFixture([.redirect("https://other.example.test/collect")])
        do { _ = try await resolver(fixture).resolve(media: from, apiKey: key); XCTFail("Metadata redirect must fail") }
        catch { XCTAssertEqual(error as? DaraTechDownloadError, .http(status: 302, retryAfter: nil)) }
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertEqual(fixture.requests.first?.url?.host, "apimovie.runflix.name.ng")
    }

    func testMalformedOversizedAndUnauthorizedMetadataMakeNoMediaRequest() async {
        for reply in [DaraTechFixture.Reply.body(Data("<html>Unavailable</html>".utf8)),
                      .body(Data(repeating: 65, count: 512 * 1024 + 1)),
                      .body(Data(), status: 401), .json(["success": false, "items": []])] {
            let fixture = DaraTechFixture([reply])
            do { _ = try await resolver(fixture).resolve(media: from, apiKey: key); XCTFail("Invalid metadata accepted") }
            catch { XCTAssertTrue(error is DaraTechDownloadError) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testCancellationStopsPendingMetadataBeforeAnySourceRequest() async {
        let started = expectation(description: "Local metadata request started")
        let fixture = DaraTechFixture([.pending(started)])
        let task = Task { try await resolver(fixture).resolve(media: from, apiKey: key) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testNativeValidationFailureDoesNotChangeQualityOrReturnUnverifiedFile() async {
        let fixture = DaraTechFixture([.json(search([fromIdentity])), .json(downloads([fromFile()])),
                                      .video(Self.movie(width: 1920, height: 1080))])
        let adapter = DaraTechDownloadResolver(session: fixture.session,
            validateNativeSource: { _ in throw OfflineSourceValidationError.unavailable })
        do { _ = try await adapter.resolve(media: from, apiKey: key); XCTFail("Native validation was bypassed") }
        catch { XCTAssertTrue(error is OfflineSourceValidationError) }
        XCTAssertEqual(fixture.requests.count, 3)
    }

    func testMissingKeyAndUnverifiableCatalogIdentityDoNotStartNetworkWork() async {
        let fixture = DaraTechFixture([])
        for invalidKey in ["", "line\nbreak", "has space"] {
            do { _ = try await resolver(fixture).resolve(media: from, apiKey: invalidKey); XCTFail("Invalid key accepted") }
            catch { XCTAssertTrue(error is DaraTechDownloadError) }
        }
        do { _ = try await resolver(fixture).resolve(media: MediaItem(id: 124364, kind: .tv, title: "From"), apiKey: key); XCTFail("Missing year accepted") }
        catch { XCTAssertEqual(error as? DaraTechDownloadError, .identityUnavailable) }
        do { _ = try await resolver(fixture).resolve(media: from, apiKey: key, season: 0); XCTFail("Invalid season accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .invalidEpisode) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testAlreadyRejectedExactURLIsExcludedWithoutTryingAnotherTier() async {
        let fixture = DaraTechFixture([.json(search([fromIdentity])),
            .json(downloads([fromFile(), file("https://cdn.example.test/480.mp4", quality: 480)]))])
        do { _ = try await resolver(fixture).resolve(media: from, apiKey: key, excludingSources: [fromURL()]); XCTFail("Excluded source accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .incompatibleSource) }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    private func resolver(_ fixture: DaraTechFixture) -> DaraTechDownloadResolver {
        // These parser/transport tests deliberately substitute only the native
        // asset load. Actual MP4 probe, dimensions and source headers run above.
        DaraTechDownloadResolver(session: fixture.session, validateNativeSource: { _ in })
    }
    private var fromIdentity: [String: Any] { identity(id: "267563007482495928", title: "From", year: 2022, type: 1) }
    private func identity(id: String, title: String, year: Int, type: Int) -> [String: Any] {
        ["id": id, "subjectId": id, "title": title, "year": year, "subjectType": type,
         "category": type == 1 ? "TV Show" : type == 2 ? "Movie" : "General"]
    }
    private func search(_ items: [[String: Any]]) -> [String: Any] { ["status": 200, "success": true, "items": items] }
    private func downloads(_ links: [[String: Any]]) -> [String: Any] { ["status": 200, "success": true, "links": links] }
    private func fromURL(episode: Int = 1) -> String {
        "https://apimovie.runflix.name.ng/v1/media/download/267563007482495928/1080?se=1&ep=\(episode)"
    }
    private func fromFile(episode: Int = 1) -> [String: Any] {
        file(fromURL(episode: episode), size: episode == 1 ? 3_129_932_601 : 2_309_577_744)
    }
    private func file(_ url: String, quality: Int = 1080, size: Int = 100_000) -> [String: Any] {
        ["quality": "\(quality)p HD", "resolution": quality, "url": url, "size": size,
         "sizeBytes": size, "format": "mp4", "requireMemberType": 0]
    }
    private static func movie(width: Int, height: Int) -> Data {
        func box(_ kind: String, _ body: Data) -> Data {
            var size = UInt32(body.count + 8).bigEndian
            return withUnsafeBytes(of: &size) { Data($0) } + Data(kind.utf8) + body
        }
        var visual = Data(repeating: 0, count: 78)
        visual[24] = UInt8((width >> 8) & 255); visual[25] = UInt8(width & 255)
        visual[26] = UInt8((height >> 8) & 255); visual[27] = UInt8(height & 255)
        let stsd = box("stsd", Data([0, 0, 0, 0, 0, 0, 0, 1]) + box("avc1", visual))
        return box("ftyp", Data("isom0000".utf8)) + box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd)))))
    }
}

private actor DaraTechNativeChecks {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

private final class DaraTechFixture {
    enum Reply {
        case body(Data, status: Int = 200, headers: [String: String] = [:])
        case video(Data), pending(XCTestExpectation), redirect(String)
        static func json(_ object: [String: Any]) -> Reply {
            .body(try! JSONSerialization.data(withJSONObject: object), headers: ["Content-Type": "application/json"])
        }
    }
    let session: URLSession
    private let scenario: DaraTechScenario
    private let id = UUID().uuidString
    var requests: [URLRequest] { scenario.requests }
    init(_ replies: [Reply]) {
        scenario = DaraTechScenario(replies)
        DaraTechProtocol.register(scenario, id: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DaraTechProtocol.self]
        configuration.httpAdditionalHeaders = ["X-DaraTech-Fixture": id]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); DaraTechProtocol.unregister(id) }
}

private final class DaraTechScenario {
    private let lock = NSLock()
    private var replies: [DaraTechFixture.Reply]
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(_ replies: [DaraTechFixture.Reply]) { self.replies = replies }
    func next(_ request: URLRequest) -> DaraTechFixture.Reply? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}

private final class DaraTechProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: DaraTechScenario] = [:]
    static func register(_ scenario: DaraTechScenario, id: String) { lock.lock(); defer { lock.unlock() }; scenarios[id] = scenario }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-DaraTech-Fixture").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        guard let reply = scenario?.next(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        switch reply {
        case .pending(let started): started.fulfill()
        case .redirect(let address):
            var redirect = request; redirect.url = URL(string: address)
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": address])!
            client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case .video(let data):
            respond(data, status: 206, headers: ["Content-Type": "video/mp4", "Content-Length": "\(data.count)",
                                               "Content-Range": "bytes 0-\(data.count - 1)/\(data.count)", "ETag": "local-video"])
        case .body(let data, let status, let headers): respond(data, status: status, headers: headers)
        }
    }
    private func respond(_ data: Data, status: Int, headers: [String: String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
