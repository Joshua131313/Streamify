import Foundation
import XCTest
@testable import Streamify

/// Normal provider response shapes with synthetic tokens and URLs. Every
/// request is intercepted locally; no live API, native network or key is used.
final class VixSrcDownloadResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let from = MediaItem(id: 124364, kind: .tv, title: "FROM", releaseDate: "2022-02-20")
    private let inception = MediaItem(id: 27205, kind: .movie, title: "Inception", releaseDate: "2010-07-15")

    func testFROM1080UsesExactAdvertisedVODAndEnglishWithoutFetchingKeysOrSegments() async throws {
        let fixture = VixFixture(responses())
        let checks = VixNativeChecks()
        let result = try await resolver(fixture, checks: checks).resolve(media: from)
        XCTAssertEqual(result.url.path, "/playlist/249336")
        XCTAssertEqual(result.url.query, "token=fixture-master-token&expires=1700003600&h=1&lang=en")
        let query = URLComponents(url: result.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }),
            ["token": "fixture-master-token", "expires": "1700003600", "h": "1", "lang": "en"])
        XCTAssertEqual(result.quality, 1080)
        XCTAssertEqual(result.actualWidth, 1920); XCTAssertEqual(result.actualHeight, 1080)
        XCTAssertEqual(result.actualCodecs, ["avc1.640028", "mp4a.40.2"])
        XCTAssertEqual(result.sourceID, "VixSrc"); XCTAssertEqual(result.transport, .hlsVOD)
        XCTAssertEqual(result.audioLanguage, "en"); XCTAssertEqual(result.headers, [:]); XCTAssertFalse(result.requiresProxy)
        XCTAssertEqual(result.expiresAt, now.addingTimeInterval(3600))
        let descriptor = try XCTUnwrap(result.hlsSource)
        XCTAssertEqual(descriptor.masterURL, result.url); XCTAssertEqual(descriptor.quality, 1080)
        XCTAssertEqual(descriptor.audioLanguage, "en"); XCTAssertEqual(descriptor.protection, .clearOrIdentityAES128)
        XCTAssertTrue(descriptor.isVOD)
        XCTAssertEqual(fixture.requests.count, 5)
        XCTAssertEqual(fixture.requests[0].url?.path, "/api/tv/124364/1/1")
        XCTAssertEqual(fixture.requests[1].url?.path, "/embed/249336")
        XCTAssertEqual(fixture.requests[3].url?.query, "rendition=1080&type=video")
        XCTAssertEqual(fixture.requests[4].url?.query, "rendition=en&type=audio")
        for request in fixture.requests {
            XCTAssertEqual(request.url?.scheme, "https"); XCTAssertEqual(request.url?.host, "vixsrc.to")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
            XCTAssertFalse(request.url?.path.contains("key") == true)
            XCTAssertFalse(request.url?.path.contains("segment") == true)
        }
        let native = await checks.selections
        XCTAssertEqual(native.count, 1); XCTAssertEqual(native[0].masterURL, result.url)
        XCTAssertEqual(native[0].videoURL.query, "rendition=1080&type=video")
        XCTAssertEqual(native[0].englishAudioURL.query, "rendition=en&type=audio")
    }

    func testMovieUsesExactTMDBMovieRouteInsteadOfTVDefaults() async throws {
        let fixture = VixFixture(responses())
        _ = try await resolver(fixture).resolve(media: inception, season: 99, episode: 88)
        XCTAssertEqual(fixture.requests[0].url?.path, "/api/movie/27205")
        XCTAssertEqual(fixture.requests[0].value(forHTTPHeaderField: "Referer"), "https://vixsrc.to/movie/27205")
    }

    func testSourceMustAdvertiseFullHDPermissionBeforeRequestingIts1080Manifest() async {
        for flag in ["", "&canPlayFHD=0"] {
            let fixture = VixFixture([.json(["src": "/embed/249336?token=fixture&expires=1700000010&lang=en\(flag)"])])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Unadvertised Full HD was requested") }
            catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .qualityUnavailable) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testEpisodeResolutionIsFreshAndKeepsExactSeasonAndEpisode() async throws {
        let fixture = VixFixture(responses() + responses())
        let adapter = resolver(fixture)
        _ = try await adapter.resolve(media: from)
        _ = try await adapter.resolve(media: from, season: 2, episode: 3)
        XCTAssertEqual(fixture.requests.count, 10)
        XCTAssertEqual(fixture.requests[5].url?.path, "/api/tv/124364/2/3")
        XCTAssertEqual(fixture.requests[6].value(forHTTPHeaderField: "Referer"), "https://vixsrc.to/tv/124364/2/3")
    }

    func test720SelectsOnlyActuallyAdvertised720AndRetainsItsNativeDimensions() async throws {
        let fixture = VixFixture(responses())
        let checks = VixNativeChecks()
        let result = try await resolver(fixture, checks: checks).resolve(media: from, quality: 720)
        XCTAssertEqual(result.quality, 720); XCTAssertEqual(result.actualWidth, 1280); XCTAssertEqual(result.actualHeight, 720)
        XCTAssertEqual(result.hlsSource?.quality, 720)
        XCTAssertEqual(fixture.requests[3].url?.query, "rendition=720&type=video")
    }

    func testMissingExact1080DoesNotProbe720OrInventAVariant() async {
        let fixture = VixFixture([api(), .text(embed()), .text(master(include1080: false))])
        let checks = VixNativeChecks()
        do { _ = try await resolver(fixture, checks: checks).resolve(media: from); XCTFail("Missing exact quality must fail") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .qualityUnavailable) }
        XCTAssertEqual(fixture.requests.count, 3)
        let native = await checks.selections; XCTAssertTrue(native.isEmpty)
    }

    func testInvalidMediaEpisodeAndUnsupportedQualityStartNoRequest() async {
        let fixture = VixFixture([])
        let adapter = resolver(fixture)
        do { _ = try await adapter.resolve(media: from, season: 0); XCTFail("Invalid episode accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .invalidEpisode) }
        do { _ = try await adapter.resolve(media: from, quality: 480); XCTFail("Unsupported tier accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .qualityUnavailable) }
        do { _ = try await adapter.resolve(media: MediaItem(id: -1, kind: .movie, title: "Bad")); XCTFail("Invalid identity accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .unsupportedMedia) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testCrossOriginInsecureCredentialedAndWrongRouteEmbedsStopBeforeHTML() async {
        for src in ["https://other.example.test/embed/249336?expires=1700000010", "http://vixsrc.to/embed/249336?expires=1700000010",
                    "https://user:pass@vixsrc.to/embed/249336?expires=1700000010", "/proxy/249336?expires=1700000010",
                    "/embed/249336?expires=1700000010#fragment"] {
            let fixture = VixFixture([.json(["src": src])])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Unsafe embed accepted") }
            catch { XCTAssertTrue(error is VixSrcDownloadError) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testExpiredEmbedAndNonEnglishLanguageAreNotRefetchedOrModified() async {
        for (src, expected) in [
            ("/embed/249336?expires=1699999999&lang=en", VixSrcDownloadError.expiredSource),
            ("/embed/249336?expires=1700000010&lang=ita", .englishAudioUnavailable)
        ] {
            let fixture = VixFixture([.json(["src": src])])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Expired or non-English embed accepted") }
            catch { XCTAssertEqual(error as? VixSrcDownloadError, expected) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testChallengeHTMLAndMissingPlainPublishedMasterStopWithoutBypass() async {
        for html in ["<html>cf-chl-challenge-platform</html>", "<script>eval(encryptedSource)</script>"] {
            let fixture = VixFixture([api(), .text(html)])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("No plain published master") }
            catch { XCTAssertEqual(error as? VixSrcDownloadError, .invalidResponse) }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    func testMasterMustBeSameOriginSameAdvertisedResourceAndUnexpired() async {
        for html in [embed().replacingOccurrences(of: "https://vixsrc.to/playlist/249336", with: "https://other.example.test/playlist/249336"),
                     embed().replacingOccurrences(of: "/playlist/249336", with: "/playlist/999999"),
                     embed(expiry: 1_699_999_999)] {
            let fixture = VixFixture([api(), .text(html)])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Unverified master accepted") }
            catch { XCTAssertTrue(error is VixSrcDownloadError) }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    func testEnglishAudioMustBelongToTheSelectedVideoGroup() async {
        let wrongGroup = master().replacingOccurrences(of: "GROUP-ID=\"audio\",LANGUAGE=\"eng\"", with: "GROUP-ID=\"other\",LANGUAGE=\"eng\"")
        let fixture = VixFixture([api(), .text(embed()), .text(wrongGroup)])
        do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Unrelated audio group accepted") }
        catch { XCTAssertEqual(error as? VixSrcDownloadError, .englishAudioUnavailable) }
        XCTAssertEqual(fixture.requests.count, 3)
    }

    func testBothSelectedVideoAndEnglishAudioMustBeCompleteVOD() async {
        for invalidAudio in [false, true] {
            let live = vod().replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")
            let replies: [VixFixture.Reply] = [api(), .text(embed()), .text(master()),
                .text(invalidAudio ? vod() : live)] + (invalidAudio ? [.text(live)] : [])
            let fixture = VixFixture(replies)
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Incomplete VOD accepted") }
            catch { XCTAssertEqual(error as? VixSrcDownloadError, .notVOD) }
            XCTAssertEqual(fixture.requests.count, invalidAudio ? 5 : 4)
        }
    }

    func testFairPlaySampleAESAndForeignKeyFormatsAreRejectedWithoutKeyRequests() async {
        for key in ["#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://asset\",KEYFORMAT=\"com.apple.streamingkeydelivery\"",
                    "#EXT-X-KEY:METHOD=AES-128,URI=\"https://cdn.example.test/key\",KEYFORMAT=\"com.apple.streamingkeydelivery\"",
                    "#EXT-X-KEY:METHOD=AES-128", "#EXT-X-KEY:METHOD=NONE,URI=\"https://cdn.example.test/key\""] {
            let fixture = VixFixture([api(), .text(embed()), .text(master()), .text(vod(key: key))])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Unsupported protection accepted") }
            catch { XCTAssertEqual(error as? VixSrcDownloadError, .unsupportedProtection) }
            XCTAssertEqual(fixture.requests.count, 4)
            XCTAssertFalse(fixture.requests.contains { $0.url?.path == "/key" })
        }
    }

    func testInsecureSegmentsAndMalformedDuplicateAttributesFailBeforeNativeCheck() async {
        for content in [vod().replacingOccurrences(of: "https://cdn.example.test/segment.ts", with: "http://cdn.example.test/segment.ts"),
                        vod(key: "#EXT-X-KEY:METHOD=AES-128,METHOD=NONE,URI=\"https://cdn.example.test/key\"")] {
            let fixture = VixFixture([api(), .text(embed()), .text(master()), .text(content)])
            let checked = VixNativeChecks()
            do { _ = try await resolver(fixture, checks: checked).resolve(media: from); XCTFail("Unsafe manifest accepted") }
            catch { XCTAssertTrue(error is VixSrcDownloadError) }
            let native = await checked.selections; XCTAssertTrue(native.isEmpty)
            XCTAssertEqual(fixture.requests.count, 4)
        }
    }

    func testNativeEvidenceCannotSubstituteLowerQualityOrAnotherVariant() async {
        for otherURL in [false, true] {
            let fixture = VixFixture(responses())
            let adapter = VixSrcDownloadResolver(session: fixture.session, now: { self.now }, nativeCapability: { selected in
                VixSrcNativeCapability(variantURL: otherURL ? URL(string: "https://vixsrc.to/playlist/other")! : selected.videoURL,
                    width: otherURL ? 1920 : 1280, height: otherURL ? 1080 : 720, audioLanguage: "en", englishAudioPlayable: true)
            })
            do { _ = try await adapter.resolve(media: from); XCTFail("Native exact-quality proof was bypassed") }
            catch { XCTAssertEqual(error as? VixSrcDownloadError, .nativeCapabilityUnavailable) }
            XCTAssertEqual(fixture.requests.count, 5)
        }
    }

    func testNativeEnglishMustBePlayableAndSelected() async {
        for playable in [false, true] {
            let fixture = VixFixture(responses())
            let adapter = VixSrcDownloadResolver(session: fixture.session, now: { self.now }, nativeCapability: { selected in
                VixSrcNativeCapability(variantURL: selected.videoURL, width: selected.width, height: selected.height,
                    audioLanguage: playable ? "ita" : "en", englishAudioPlayable: playable)
            })
            do { _ = try await adapter.resolve(media: from); XCTFail("Unplayable or other-language audio accepted") }
            catch { XCTAssertEqual(error as? VixSrcDownloadError, .englishAudioUnavailable) }
            XCTAssertEqual(fixture.requests.count, 5)
        }
    }

    func testNativeTransportFailurePropagatesWithoutQualityFallback() async {
        let fixture = VixFixture(responses())
        let adapter = VixSrcDownloadResolver(session: fixture.session, now: { self.now }, nativeCapability: { _ in throw URLError(.cannotConnectToHost) })
        do { _ = try await adapter.resolve(media: from); XCTFail("Transport failure accepted") }
        catch { XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost) }
        XCTAssertEqual(fixture.requests.count, 5)
    }

    func testRateLimitStatusAndRetryAfterArePreservedWithoutRetry() async {
        let fixture = VixFixture([.body(Data(), status: 429, headers: ["Retry-After": "45"])])
        do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Rate limit accepted") }
        catch { XCTAssertEqual(error as? VixSrcDownloadError, .http(status: 429, retryAfter: "45")) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testMalformedOversizedAndDuplicateQueryMetadataNeverReachNative() async {
        for reply in [VixFixture.Reply.text("<html>not json</html>"), .body(Data(repeating: 65, count: 32 * 1024 + 1)),
                      .json(["src": "/embed/249336?expires=1700000010&expires=1700000020"])] {
            let fixture = VixFixture([reply])
            do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Malformed metadata accepted") }
            catch { XCTAssertTrue(error is VixSrcDownloadError || error is CocoaError) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testMetadataRedirectIsRefusedWithoutAnotherOriginRequest() async {
        let fixture = VixFixture([.redirect("https://other.example.test/collect")])
        do { _ = try await resolver(fixture).resolve(media: from); XCTFail("Redirect accepted") }
        catch { XCTAssertEqual(error as? VixSrcDownloadError, .redirectRefused(status: 302)) }
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "vixsrc.to" })
    }

    func testCallerCancellationStopsPendingMetadataBeforeAnotherFetch() async {
        let started = expectation(description: "Local request started")
        let stopped = expectation(description: "Native URLSession request stopped")
        let fixture = VixFixture([.pending(started, stopped)])
        let adapter = resolver(fixture)
        let task = Task { try await adapter.resolve(media: from) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Caller cancellation was lost") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testExcludedReturnedMasterIsNotFetchedOrReplacedWithInventedSource() async {
        let fixture = VixFixture([api(), .text(embed())])
        let address = "https://vixsrc.to/playlist/249336?token=fixture-master-token&expires=1700003600&h=1&lang=en"
        do { _ = try await resolver(fixture).resolve(media: from, excludingSources: [address]); XCTFail("Excluded master accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .incompatibleSource) }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    private func resolver(_ fixture: VixFixture, checks: VixNativeChecks = VixNativeChecks()) -> VixSrcDownloadResolver {
        let timestamp = now
        return VixSrcDownloadResolver(session: fixture.session, now: { timestamp }, nativeCapability: { selected in
            await checks.record(selected)
            return VixSrcNativeCapability(variantURL: selected.videoURL, width: selected.width, height: selected.height,
                audioLanguage: "en", englishAudioPlayable: true)
        })
    }
    private func api() -> VixFixture.Reply {
        .json(["src": "/embed/249336?token=fixture-embed-token&expires=1700000010&lang=en&canPlayFHD=1"])
    }
    private func embed(expiry: Int = 1_700_003_600) -> String {
        """
        window.masterPlaylist = {
            params: {'token': 'fixture-master-token', 'expires': '\(expiry)', 'asn': ''},
            url: 'https://vixsrc.to/playlist/249336',
        }
        """
    }
    private func master(include1080: Bool = true) -> String {
        """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="ita",NAME="Italian",URI="/playlist/249336?rendition=it&type=audio"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="eng",NAME="English",URI="/playlist/249336?rendition=en&type=audio"
        #EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio"
        /playlist/249336?rendition=720&type=video
        """ + (include1080 ? "\n#EXT-X-STREAM-INF:BANDWIDTH=3800000,RESOLUTION=1920x1080,CODECS=\"avc1.640028,mp4a.40.2\",AUDIO=\"audio\"\n/playlist/249336?rendition=1080&type=video\n" : "\n")
    }
    private func vod(key: String = "#EXT-X-KEY:METHOD=AES-128,URI=\"https://cdn.example.test/key\",KEYFORMAT=\"identity\"") -> String {
        """
        #EXTM3U
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-TARGETDURATION:8
        \(key)
        #EXTINF:8,
        https://cdn.example.test/segment.ts
        #EXT-X-ENDLIST
        """
    }
    private func responses() -> [VixFixture.Reply] {
        [api(), .text(embed()), .text(master()), .text(vod()), .text(vod(key: "#EXT-X-KEY:METHOD=NONE"))]
    }
}

private actor VixNativeChecks {
    private(set) var selections: [VixSrcDownloadSelection] = []
    func record(_ selection: VixSrcDownloadSelection) { selections.append(selection) }
}
private final class VixFixture {
    enum Reply {
        case body(Data, status: Int = 200, headers: [String: String] = [:])
        case pending(XCTestExpectation, XCTestExpectation), redirect(String)
        static func text(_ value: String) -> Self { .body(Data(value.utf8)) }
        static func json(_ value: [String: Any]) -> Self { .body(try! JSONSerialization.data(withJSONObject: value)) }
    }
    let session: URLSession
    private let scenario: VixScenario
    private let id = UUID().uuidString
    var requests: [URLRequest] { scenario.requests }
    init(_ replies: [Reply]) {
        scenario = VixScenario(replies); VixProtocol.register(scenario, id: id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VixProtocol.self]; config.httpAdditionalHeaders = ["X-Vix-Fixture": id]
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        session = URLSession(configuration: config)
    }
    deinit { session.invalidateAndCancel(); VixProtocol.unregister(id) }
}
private final class VixScenario {
    private let lock = NSLock()
    private var replies: [VixFixture.Reply]
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(_ replies: [VixFixture.Reply]) { self.replies = replies }
    func next(_ request: URLRequest) -> VixFixture.Reply? {
        lock.lock(); defer { lock.unlock() }; recorded.append(request)
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}
private final class VixProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: VixScenario] = [:]
    private let stopLock = NSLock()
    private var stopped: XCTestExpectation?
    static func register(_ value: VixScenario, id: String) { lock.lock(); defer { lock.unlock() }; scenarios[id] = value }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let scenario = request.value(forHTTPHeaderField: "X-Vix-Fixture").flatMap { Self.scenarios[$0] }; Self.lock.unlock()
        guard let reply = scenario?.next(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        switch reply {
        case .pending(let started, let cancelled):
            stopLock.lock(); stopped = cancelled; stopLock.unlock(); started.fulfill()
        case .redirect(let target):
            var redirected = request; redirected.url = URL(string: target)
            client?.urlProtocol(self, wasRedirectedTo: redirected,
                redirectResponse: HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!)
            client?.urlProtocolDidFinishLoading(self)
        case .body(let data, let status, let headers):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        stopLock.lock(); let done = stopped; stopped = nil; stopLock.unlock(); done?.fulfill()
    }
}
