import Foundation
import XCTest
@testable import Streamify

/// Captured response shapes and intercepted HTTP only; no live player or API.
final class StreamFreeProviderTests: XCTestCase {
    func testAllSixLeaguesRequireTheirOwnLeagueBothTeamsAndDate() {
        for league in SportsLeague.allCases where league != .tennis {
            let game = StreamFreeSnapshots.game(league)
            let item = StreamFreeSnapshots.item(game)
            XCTAssertTrue(StreamFreeProvider.matches(item, game: game, now: StreamFreeSnapshots.now), "Missing \(league)")
            var wrong = item; wrong["category"] = league.sport == "hockey" ? "basketball" : "hockey"
            XCTAssertFalse(StreamFreeProvider.matches(wrong, game: game, now: StreamFreeSnapshots.now))
            wrong = item; wrong["league"] = league == .wnba ? "NBA" : "WNBA"
            XCTAssertFalse(StreamFreeProvider.matches(wrong, game: game, now: StreamFreeSnapshots.now))
            wrong = item; wrong["name"] = "Unrelated Team vs \(game.home.name)"
            XCTAssertFalse(StreamFreeProvider.matches(wrong, game: game, now: StreamFreeSnapshots.now))
            wrong = item; wrong["match_timestamp"] = StreamFreeSnapshots.start.addingTimeInterval(24 * 3600).timeIntervalSince1970
            XCTAssertFalse(StreamFreeProvider.matches(wrong, game: game, now: StreamFreeSnapshots.now))
        }
    }

    func testCollegeAliasesAreExactAndDoNotConfuseAlabamaWithAlabamaState() {
        let game = StreamFreeSnapshots.game(.ncaaf)
        var item = StreamFreeSnapshots.item(game)
        item["name"] = "Alabama vs Georgia"
        XCTAssertTrue(StreamFreeProvider.matches(item, game: game, now: StreamFreeSnapshots.now))
        item["name"] = "Alabama State vs Georgia"
        XCTAssertFalse(StreamFreeProvider.matches(item, game: game, now: StreamFreeSnapshots.now))
        item["name"] = "Crimson Tide vs Bulldogs"
        XCTAssertFalse(StreamFreeProvider.matches(item, game: game, now: StreamFreeSnapshots.now))
    }

    func testMissingUnsafeOrMillisecondsDatesCannotCreatePlayerRequests() {
        let game = StreamFreeSnapshots.game(.nba)
        let original = StreamFreeSnapshots.item(game)
        let invalidDates: [Any] = [0, -1, true, StreamFreeSnapshots.start.timeIntervalSince1970 * 1000, "1793066400", NSNull()]
        for value in invalidDates {
            var item = original; item["match_timestamp"] = value
            XCTAssertFalse(StreamFreeProvider.matches(item, game: game, now: StreamFreeSnapshots.now))
        }
        for key in ["", "../another-game", "game/key", "key?server=1", "key#fragment", String(repeating: "a", count: 201)] {
            var item = original; item["stream_key"] = key
            XCTAssertFalse(StreamFreeProvider.matches(item, game: game, now: StreamFreeSnapshots.now))
        }
        var numericKey = original; numericKey["stream_key"] = 123
        XCTAssertFalse(StreamFreeProvider.matches(numericKey, game: game, now: StreamFreeSnapshots.now))
    }

    func testNormalMirrorResolutionMatchesTheActualPublicWatchPageAndDropsQueryAndFragment() throws {
        let key = StreamFreeSnapshots.key
        let raw = "https://strmfree.st/embed/basketball/\(key)1080p3?server=ignored#unused"
        let value = try XCTUnwrap(StreamFreeProvider.normalSource(raw, key: key, category: "basketball"))
        XCTAssertEqual(value.url.absoluteString, "https://streamfree.top/embed/basketball/\(key)1080p3")
        XCTAssertEqual(value.quality, "1080p")
        XCTAssertEqual(value.server, 3)
        let current = try XCTUnwrap(StreamFreeProvider.normalSource("https://streamfree.top/embed/basketball/\(key)720p2", key: key, category: "basketball"))
        XCTAssertEqual(current.server, 2)
        XCTAssertEqual(current.quality, "720p")
    }

    func testOtherHostsCredentialsHTTPPortsTraversalAndOtherGamesAreRejected() {
        let key = StreamFreeSnapshots.key
        let path = "/embed/basketball/\(key)1080p3"
        for raw in ["http://strmfree.st" + path, "https://unlisted.example" + path,
            "https://streamfree.top.evil.example" + path, "https://user:password@streamfree.top" + path,
            "https://strmfree.st:8443" + path, "https://strmfree.st/other" + path,
            "https://strmfree.st/embed/hockey/\(key)1080p3", "https://strmfree.st/embed/basketball/other-game1080p3",
            "https://strmfree.st/embed/basketball/\(key)%2Fother", "https://strmfree.st/embed/basketball/../\(key)",
            "https://strmfree.st/embed//basketball/\(key)", "/embed/basketball/\(key)", "javascript:alert(1)"] {
            XCTAssertNil(StreamFreeProvider.normalSource(raw, key: key, category: "basketball"), raw)
        }
    }

    func testCapturedNBAAndNHLShapesResolveOnlyPublishedVariants() async throws {
        for league in [SportsLeague.nba, .nhl] {
            let fixture = StreamFreeFixture(.success, league: league)
            let game = StreamFreeSnapshots.game(league)
            let provider = StreamFreeProvider(session: fixture.session, now: { StreamFreeSnapshots.now })
            let streams = try await provider.streams(game)
            let key = StreamFreeSnapshots.key(for: league)
            XCTAssertEqual(streams.map(\.url.absoluteString), ["https://streamfree.top/embed/\(league.sport)/\(key)1080p3"])
            XCTAssertEqual(streams.map(\.title), ["StreamFree · 1080p · Source 3"])
            XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/v1/streams", "/api/v1/sources/" + key])
            XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "streamfree.top" })
        }
    }

    func testCatalogStaysWarmButEachWatchFetchesCurrentVariantsAgain() async throws {
        let fixture = StreamFreeFixture(.changingSources)
        let provider = StreamFreeProvider(session: fixture.session, now: { StreamFreeSnapshots.now })
        let first = try await provider.streams(StreamFreeSnapshots.game(.nba))
        let second = try await provider.streams(StreamFreeSnapshots.game(.nba))
        XCTAssertTrue(try XCTUnwrap(first.first).url.path.hasSuffix("1080p3"))
        XCTAssertTrue(try XCTUnwrap(second.first).url.path.hasSuffix("720p2"))
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/v1/streams", "/api/v1/sources/" + StreamFreeSnapshots.key, "/api/v1/sources/" + StreamFreeSnapshots.key])
    }

    func testUnrelatedCatalogDoesNotGuessAnEmbedOrRequestSources() async throws {
        let fixture = StreamFreeFixture(.unrelated)
        let provider = StreamFreeProvider(session: fixture.session, now: { StreamFreeSnapshots.now })
        let streams = try await provider.streams(StreamFreeSnapshots.game(.nba))
        XCTAssertTrue(streams.isEmpty)
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/v1/streams"])
    }

    func testEmptyAndPartialSourceListsRemainUsableAndDedupeNormalMirrorURLs() async throws {
        let empty = StreamFreeFixture(.emptySources)
        let emptyValues = try await StreamFreeProvider(session: empty.session, now: { StreamFreeSnapshots.now }).streams(StreamFreeSnapshots.game(.nba))
        XCTAssertTrue(emptyValues.isEmpty)
        let partial = StreamFreeFixture(.partialSources)
        let values = try await StreamFreeProvider(session: partial.session, now: { StreamFreeSnapshots.now }).streams(StreamFreeSnapshots.game(.nba))
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.url.host, "streamfree.top")
    }

    func testChangedSourceKeyIsRejectedInsteadOfStartingAnotherGame() async throws {
        let fixture = StreamFreeFixture(.wrongSourceKey)
        do {
            _ = try await StreamFreeProvider(session: fixture.session, now: { StreamFreeSnapshots.now }).streams(StreamFreeSnapshots.game(.nba))
            XCTFail("A different returned source identity must be rejected.")
        } catch { guard case .invalidResponse? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
    }

    func testHTTPAndTransportFailuresDoNotBecomeAlternateSources() async throws {
        let denied = StreamFreeFixture(.sourceHTTP(403))
        do {
            _ = try await StreamFreeProvider(session: denied.session, now: { StreamFreeSnapshots.now }).streams(StreamFreeSnapshots.game(.nba))
            XCTFail("A denied endpoint must be respected.")
        } catch { guard case .unavailable(403)? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
        XCTAssertEqual(denied.requests.count, 2)
        let failed = StreamFreeFixture(.transport(.notConnectedToInternet))
        do {
            _ = try await StreamFreeProvider(session: failed.session, now: { StreamFreeSnapshots.now }).streams(StreamFreeSnapshots.game(.nba))
            XCTFail("The transport must fail.")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(failed.requests.count, 1)
    }

    func testCancellationStopsTheOwnedNetworkRequestAndCannotReturnPlayback() async throws {
        let fixture = StreamFreeFixture(.pendingCatalog)
        let provider = StreamFreeProvider(session: fixture.session, now: { StreamFreeSnapshots.now })
        let task = Task { try await provider.streams(StreamFreeSnapshots.game(.nba)) }
        await fulfillment(of: [fixture.started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled lookup must stop.") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [fixture.stopped], timeout: 2)
        XCTAssertEqual(fixture.requests.count, 1)
    }
}

private enum StreamFreeSnapshots {
    static let start = Date(timeIntervalSince1970: 1_793_066_400)
    static let now = start.addingTimeInterval(3600)
    static let key = "golden-state-warriors-vs-denver-nuggets"
    static func key(for league: SportsLeague) -> String { league == .nba ? key : league == .nhl ? "detroit-red-wings-vs-edmonton-oilers" : "returned-\(league.rawValue)-event" }
    static func game(_ league: SportsLeague) -> SportsGame {
        let teams: (String, String)
        switch league {
        case .nba: teams = ("Denver Nuggets", "Golden State Warriors")
        case .wnba: teams = ("Las Vegas Aces", "New York Liberty")
        case .nfl: teams = ("Philadelphia Eagles", "Dallas Cowboys")
        case .ncaaf: teams = ("Georgia Bulldogs", "Alabama Crimson Tide")
        case .nhl: teams = ("Edmonton Oilers", "Detroit Red Wings")
        case .mlb: teams = ("Tampa Bay Rays", "Milwaukee Brewers")
        case .tennis: teams = ("Jannik Sinner", "Carlos Alcaraz")
        }
        return SportsGame(eventID: "401909876", league: league, date: start, state: "in", status: "Live",
            home: SportsTeam(id: "home", name: teams.0, abbreviation: "HOME", logo: "", streamNames: league == .ncaaf ? ["Georgia"] : []),
            away: SportsTeam(id: "away", name: teams.1, abbreviation: "AWAY", logo: "", streamNames: league == .ncaaf ? ["Alabama"] : []), venue: "", broadcasts: "", link: "")
    }
    static func item(_ game: SportsGame) -> [String: Any] {
        ["name": "\(game.away.name) vs \(game.home.name)", "category": game.league.sport,
         "league": game.league == .ncaaf ? "College Football" : game.league.title,
         "stream_key": key(for: game.league), "match_timestamp": start.timeIntervalSince1970,
         "sources": ["https://strmfree.st/embed/\(game.league.sport)/\(key(for: game.league))1080p3"],
         "thumbnail_url": "https://streamfree.top/thumbnails/fixture"]
    }
}

private final class StreamFreeFixture {
    enum Mode { case success, changingSources, unrelated, emptySources, partialSources, wrongSourceKey, sourceHTTP(Int), transport(URLError.Code), pendingCatalog }
    let session: URLSession
    private let id = UUID().uuidString
    private let scenario: StreamFreeScenario
    var requests: [URLRequest] { scenario.requests }
    var started: XCTestExpectation { scenario.started }
    var stopped: XCTestExpectation { scenario.stopped }
    init(_ mode: Mode, league: SportsLeague = .nba) {
        scenario = StreamFreeScenario(mode, league: league)
        StreamFreeProtocol.register(scenario, id: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamFreeProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-StreamFree-Test": id]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); StreamFreeProtocol.unregister(id) }
}

private final class StreamFreeScenario {
    let mode: StreamFreeFixture.Mode
    let league: SportsLeague
    let started = XCTestExpectation(description: "Owned source catalog started")
    let stopped = XCTestExpectation(description: "Owned source catalog cancelled")
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var sourceCalls = 0
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(_ mode: StreamFreeFixture.Mode, league: SportsLeague) { self.mode = mode; self.league = league }
    func response(_ request: URLRequest) throws -> (Int, Data)? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let url = try XCTUnwrap(request.url)
        guard url.host == "streamfree.top", url.scheme == "https" else { throw URLError(.unsupportedURL) }
        if case .transport(let code) = mode { throw URLError(code) }
        let object: [String: Any]
        let key = StreamFreeSnapshots.key(for: league)
        if url.path == "/api/v1/streams" {
            if case .pendingCatalog = mode { started.fulfill(); return nil }
            var item = StreamFreeSnapshots.item(StreamFreeSnapshots.game(league))
            if case .unrelated = mode { item["name"] = "Other Team vs Another Team" }
            object = ["count": 1, "streams": [item]]
        } else if url.path == "/api/v1/sources/" + key {
            if case .sourceHTTP(let status) = mode { return (status, Data("{}".utf8)) }
            sourceCalls += 1
            let variant: String
            if case .changingSources = mode, sourceCalls > 1 { variant = "720p2" } else { variant = "1080p3" }
            let path = "/embed/\(league.sport)/\(key)\(variant)"
            var sources: [Any] = ["https://strmfree.st" + path]
            if case .emptySources = mode { sources = [] }
            if case .partialSources = mode {
                sources += ["https://streamfree.top" + path, "https://other.example" + path, "http://strmfree.st" + path,
                    "https://user:secret@streamfree.top" + path, NSNull(), 4]
            }
            object = ["stream_key": { if case .wrongSourceKey = mode { return "another-game" }; return key }(), "sources": sources]
        } else { throw URLError(.unsupportedURL) }
        return (200, try JSONSerialization.data(withJSONObject: object))
    }
    func stop() { if case .pendingCatalog = mode { stopped.fulfill() } }
}

private final class StreamFreeProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: StreamFreeScenario] = [:]
    private var scenario: StreamFreeScenario?
    static func register(_ value: StreamFreeScenario, id: String) { lock.lock(); defer { lock.unlock() }; scenarios[id] = value }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        scenario = request.value(forHTTPHeaderField: "X-Streamify-StreamFree-Test").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        do {
            let scenario = try XCTUnwrap(scenario)
            guard let (status, data) = try scenario.response(request) else { return }
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { scenario?.stop() }
}
