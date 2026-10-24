import Foundation
import XCTest
@testable import Streamify

final class MediaDownloadResolverTests: XCTestCase {
    func testMovieResolvesHighestAllowedFileQualityAndPreservesSignedQuery() async throws {
        let fixture = DownloadResolverFixture([
            .json(["result": "A+/=token_-"]),
            .json(["stream": ["type": "file", "qualities": [
                "1080": ["url": "https://cdn.example.test/video.mp4?expires=2000000000&signature=a%2Bb%2Fc%3D"],
                "720": ["url": "https://cdn.example.test/video-720.mp4"]
            ]]])
        ])
        let result = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
            .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
        XCTAssertEqual(result.quality, 1080)
        XCTAssertEqual(result.url.absoluteString, "https://cdn.example.test/video.mp4?expires=2000000000&signature=a%2Bb%2Fc%3D")
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://enc-dec.app/api/enc-vidlink?text=42")
        XCTAssertEqual(requests.last?.url?.absoluteString, "https://vidlink.pro/api/b/movie/A%2B%2F%3Dtoken_-")
        XCTAssertNil(requests.last?.url?.fragment)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Origin"), "https://vidlink.pro")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Referer"), "https://vidlink.pro/")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "User-Agent"), "Mozilla/5.0")
    }

    func testTVUsesEpisodeIdentityAndAcceptsSignedExtensionlessFile() async throws {
        let fixture = DownloadResolverFixture([
            .json(["result": "fixture-token"]),
            .json(["stream": ["type": "file", "qualities": [
                "1080": ["url": "https://cdn.example.test/full.mp4"],
                "720": ["url": "https://cdn.example.test/media/episode?token=abc%2Fdef&quality=720"],
                "480": ["url": "https://cdn.example.test/low.mp4"]
            ]]])
        ])
        let result = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
            .resolve(media: MediaItem(id: 84, kind: .tv, title: "Fixture series"), season: 2, episode: 7, maximumQuality: 720)
        XCTAssertEqual(result.quality, 720)
        XCTAssertEqual(result.url.absoluteString, "https://cdn.example.test/media/episode?token=abc%2Fdef&quality=720")
        XCTAssertEqual(fixture.requests.last?.url?.path, "/api/b/tv/fixture-token/2/7")
    }

    func testUnsafeSelectedQualityDoesNotSilentlyDownloadSafeLowerQuality() async throws {
        let fixture = sourceFixture(["type": "file", "qualities": [
            "1080": ["url": "http://cdn.example.test/video.mp4"],
            "720": ["url": "https://cdn.example.test/video.mp4"]
        ]])
        do {
            _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
            XCTFail("An unsafe selected source must not silently change quality")
        } catch let error as MediaDownloadResolutionError {
            guard case .unsafeSource = error else { XCTFail("Unexpected error: \(error)"); return }
        }
    }

    func testRejectsInsecureCredentialFragmentAndPageAddresses() async {
        for address in ["http://cdn.example.test/video.mp4", "https://user:secret@cdn.example.test/video.mp4",
                        "file:///tmp/video.mp4", "https://cdn.example.test/video.mp4#fragment",
                        "https://cdn.example.test:8443/video.mp4", "https://cdn.example.test/player.html",
                        "https://cdn.example.test/watch.php", "https://cdn.example.test/line\nbreak.mp4"] {
            let fixture = sourceFixture(["type": "file", "qualities": ["1080": ["url": address]]])
            do {
                _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                    .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
                XCTFail("Accepted an unsafe video address: \(address)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("HTTPS video file"))
            }
        }
    }

    func testStreamingPlaylistsAndDRMAreNeverReturnedAsDownloads() async {
        let streams: [[String: Any]] = [
            ["type": "hls", "qualities": ["1080": ["url": "https://cdn.example.test/video.mp4"]]],
            ["type": "file", "qualities": ["1080": ["url": "https://cdn.example.test/master.m3u8"]]],
            ["type": "file", "qualities": ["1080": ["url": "https://cdn.example.test/manifest.mpd"]]],
            ["type": "file", "drm": true, "qualities": ["1080": ["url": "https://cdn.example.test/video.mp4"]]],
            ["type": "file", "qualities": ["1080": ["url": "https://cdn.example.test/video.mp4", "licenseUrl": "https://license.example.test"]]]
        ]
        for stream in streams {
            let fixture = sourceFixture(stream)
            do {
                _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                    .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
                XCTFail("A playlist or DRM source must not be downloaded.")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("streaming only"))
            }
        }
    }

    func testQualityLimitDoesNotSilentlyDownloadHigherResolution() async {
        let fixture = sourceFixture(["type": "file", "qualities": ["1080": ["url": "https://cdn.example.test/video.mp4"]]])
        do {
            _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"), maximumQuality: 480)
            XCTFail("A higher resolution must not bypass the user's quality limit.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Choose another resolution"))
        }
    }

    func testInvalidIdentitiesAndEpisodeNumbersMakeNoRequest() async {
        let fixture = DownloadResolverFixture([])
        let resolver = MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
        for item in [MediaItem(id: 42, kind: .anime, title: "Anime"), MediaItem(id: 0, kind: .movie, title: "Invalid") ] {
            do { _ = try await resolver.resolve(media: item); XCTFail("Unsupported identity was accepted.") }
            catch { XCTAssertTrue(error.localizedDescription.contains("movies and TV")) }
        }
        do {
            _ = try await resolver.resolve(media: MediaItem(id: 42, kind: .tv, title: "Fixture"), season: 0, episode: 1)
            XCTFail("An invalid season was accepted.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("season and episode")) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testMalformedTokenCannotBecomeAProviderPathOrHost() async {
        for token in ["", " ", "../admin", "https://evil.example.test/path", "token#fragment", "line\nbreak", String(repeating: "A", count: 4097)] {
            let fixture = DownloadResolverFixture([.json(["result": token])])
            do {
                _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                    .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
                XCTFail("A malformed token was accepted.")
            } catch { XCTAssertTrue(error.localizedDescription.contains("unreadable response")) }
            XCTAssertEqual(fixture.requests.count, 1, "A malformed token must never reach the provider.")
        }
    }

    func testMalformedAndOversizedMetadataFailWithoutFetchingVideo() async {
        let replies: [DownloadResolverFixture.Reply] = [
            .body(Data("<html>maintenance</html>".utf8)),
            .body(Data("[]".utf8)),
            .body(Data(repeating: 65, count: 32 * 1024 + 1)),
            .body(Data("{}".utf8), status: 503),
            .body(Data(), status: 302, headers: ["Location": "https://evil.example.test/collect"])
        ]
        for reply in replies {
            let fixture = DownloadResolverFixture([reply])
            do {
                _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                    .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
                XCTFail("Invalid metadata was accepted.")
            } catch { XCTAssertTrue(error is MediaDownloadResolutionError) }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testProviderMetadataAlsoHasAByteLimit() async {
        let fixture = DownloadResolverFixture([
            .json(["result": "fixture-token"]), .body(Data(repeating: 65, count: 512 * 1024 + 1))
        ])
        do {
            _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
            XCTFail("An oversized provider response was accepted.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("unreadable response")) }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testCancellationStopsAnInFlightMetadataRequest() async {
        let started = expectation(description: "Metadata request started")
        let fixture = DownloadResolverFixture([.pending(started)])
        let task = Task {
            try await MediaDownloadResolver(session: fixture.session, sourceValidator: { _ in })
                .resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled resolution must not succeed.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testNativeIncompatibilityKeepsTheExactQualityAndRequiresAnotherUserChoice() async throws {
        let fixture = sourceFixture(["type": "file", "qualities": [
            "1080": ["url": "https://cdn.example.test/1080.mp4"],
            "720": ["url": "https://cdn.example.test/1080.mp4"],
            "480": ["url": "https://cdn.example.test/480.mp4"],
            "360": ["url": "https://cdn.example.test/360.mp4"]
        ]])
        let checked = DownloadSourceValidationProbe()
        let resolver = MediaDownloadResolver(session: fixture.session, sourceValidator: { url in
            await checked.record(url)
            if url.lastPathComponent == "1080.mp4" { throw OfflineVideoError.incompatible }
        })
        do {
            _ = try await resolver.resolve(media: MediaItem(id: 124364, kind: .tv, title: "Fixture series"),
                season: 1, episode: 1, maximumQuality: 1080)
            XCTFail("Selecting 1080p must never download 480p without another user choice")
        } catch let error as MediaDownloadResolutionError {
            guard case .incompatibleSource = error else { XCTFail("Unexpected error: \(error)"); return }
            XCTAssertTrue(error.localizedDescription.contains("selected quality"))
        }
        let paths = await checked.paths
        XCTAssertEqual(paths, ["1080.mp4"], "Lower resolutions must not be inspected or transferred without selection")
        XCTAssertEqual(fixture.requests.count, 2, "Only bounded API metadata is fetched by this injected contract test")
    }

    func testAllNativeIncompatibleFilesProduceAClearCompatibilityError() async {
        let fixture = sourceFixture(["type": "file", "qualities": [
            "1080": ["url": "https://cdn.example.test/1080.mp4"],
            "480": ["url": "https://cdn.example.test/480.mp4"]
        ]])
        let checked = DownloadSourceValidationProbe()
        do {
            _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { url in
                await checked.record(url)
                throw OfflineVideoError.incompatible
            }).resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
            XCTFail("A file the native player cannot play must not start a complete download")
        } catch let error as MediaDownloadResolutionError {
            guard case .incompatibleSource = error else { XCTFail("Unexpected source error: \(error)"); return }
            XCTAssertTrue(error.localizedDescription.contains("cannot be played by this iPhone"))
        } catch { XCTFail("Expected a source compatibility error: \(error)") }
        let paths = await checked.paths
        XCTAssertEqual(paths, ["1080.mp4"])
    }

    func testNetworkFailureDuringPreflightDoesNotBecomeACodecErrorOrTryAnotherQuality() async {
        let fixture = sourceFixture(["type": "file", "qualities": [
            "1080": ["url": "https://cdn.example.test/1080.mp4"],
            "480": ["url": "https://cdn.example.test/480.mp4"]
        ]])
        let checked = DownloadSourceValidationProbe()
        do {
            _ = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { url in
                await checked.record(url)
                throw URLError(.badServerResponse)
            }).resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"))
            XCTFail("Unavailable metadata cannot establish native compatibility")
        } catch let error as MediaDownloadResolutionError {
            guard case .unavailable = error else { XCTFail("A network failure was mislabeled: \(error)"); return }
        } catch { XCTFail("Expected an unavailable source error: \(error)") }
        let paths = await checked.paths
        XCTAssertEqual(paths, ["1080.mp4"], "A network or rate-limit error must not trigger another candidate request")
    }

    func testCancellationDuringPreflightStopsBeforeCheckingAnotherCandidate() async {
        let fixture = sourceFixture(["type": "file", "qualities": [
            "1080": ["url": "https://cdn.example.test/1080.mp4"],
            "480": ["url": "https://cdn.example.test/480.mp4"]
        ]])
        let checked = DownloadSourceValidationProbe()
        let started = expectation(description: "Native source inspection started")
        let resolver = MediaDownloadResolver(session: fixture.session, sourceValidator: { url in
            await checked.record(url)
            started.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
        })
        let task = Task { try await resolver.resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture")) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled preflight must not return a source") }
        catch { XCTAssertTrue(error is CancellationError) }
        let paths = await checked.paths
        XCTAssertEqual(paths, ["1080.mp4"])
    }

    func testPreflightDoesNotBlacklistHEVCNamesOrExceedTheSelectedQuality() async throws {
        let fixture = sourceFixture(["type": "file", "qualities": [
            "1080": ["url": "https://cdn.example.test/1080.mp4"],
            "720": ["url": "https://cdn.example.test/hev1-720.mp4"],
            "480": ["url": "https://cdn.example.test/480.mp4"]
        ]])
        let checked = DownloadSourceValidationProbe()
        let result = try await MediaDownloadResolver(session: fixture.session, sourceValidator: { url in
            await checked.record(url)
        }).resolve(media: MediaItem(id: 42, kind: .movie, title: "Fixture"), maximumQuality: 720)
        XCTAssertEqual(result.quality, 720)
        let paths = await checked.paths
        XCTAssertEqual(paths, ["hev1-720.mp4"], "Native inspection decides support; a filename or a HEVC tag is not a device capability test")
    }

    private func sourceFixture(_ stream: [String: Any]) -> DownloadResolverFixture {
        DownloadResolverFixture([.json(["result": "fixture-token"]), .json(["stream": stream])])
    }
}

private actor DownloadSourceValidationProbe {
    private var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
    var paths: [String] { urls.map(\.lastPathComponent) }
}

private final class DownloadResolverFixture {
    enum Reply {
        case body(Data, status: Int = 200, headers: [String: String] = [:])
        case pending(XCTestExpectation)

        static func json(_ object: [String: Any]) -> Reply {
            .body(try! JSONSerialization.data(withJSONObject: object), headers: ["Content-Type": "application/json"])
        }
    }

    let session: URLSession
    private let identifier = UUID().uuidString
    private let scenario: DownloadResolverScenario
    var requests: [URLRequest] { scenario.requests }

    init(_ replies: [Reply]) {
        scenario = DownloadResolverScenario(replies: replies)
        DownloadResolverProtocol.register(scenario, identifier: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadResolverProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Fixture": identifier]
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
        DownloadResolverProtocol.unregister(identifier)
    }
}

private final class DownloadResolverScenario {
    private let lock = NSLock()
    private var replies: [DownloadResolverFixture.Reply]
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(replies: [DownloadResolverFixture.Reply]) { self.replies = replies }
    func next(_ request: URLRequest) -> DownloadResolverFixture.Reply? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}

private final class DownloadResolverProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: DownloadResolverScenario] = [:]
    static func register(_ scenario: DownloadResolverScenario, identifier: String) {
        lock.lock(); defer { lock.unlock() }; scenarios[identifier] = scenario
    }
    static func unregister(_ identifier: String) {
        lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: identifier)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-Streamify-Fixture").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        guard let reply = scenario?.next(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        switch reply {
        case .pending(let started): started.fulfill()
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
