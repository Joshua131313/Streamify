import Foundation
import XCTest
@testable import Streamify

final class SportsContractTests: XCTestCase {
    func testProviderAPIClosureRedirectShowsTypedUnavailableAndDoesNotUseNoticeLinks() async throws {
        let fixture = ProviderJSONFixture(.closureRedirect)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        do { _ = try await service.streams(game); XCTFail("A closure homepage is not a stream catalog.") }
        catch { guard case .streamProviderUnavailable? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/matches/all"])
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "streamed.pk" }, "A notice's links must never become guessed playback fallbacks.")
    }

    func testProviderHTMLAtAnAPIURLShowsTypedUnavailableAndIsNotCached() async throws {
        let fixture = ProviderJSONFixture(.closureHTML)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        for _ in 0..<2 {
            do { _ = try await service.streams(game); XCTFail("HTML is not a match response.") }
            catch { guard case .streamProviderUnavailable? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
        }
        XCTAssertEqual(fixture.requests.count, 2, "Closure HTML must not enter the warm catalog cache.")
    }

    func testProviderMalformedJSONHasReadableInvalidResponseWithoutClaimingClosure() async throws {
        let fixture = ProviderJSONFixture(.invalidJSON)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        do { _ = try await service.streams(game); XCTFail("Malformed JSON must be rejected.") }
        catch { guard case .invalidResponse? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
    }

    func testSuccessfulProviderJSONStillResolvesOnlyItsMatchedSources() async throws {
        let fixture = ProviderJSONFixture(.success)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        let streams = try await service.streams(game)
        XCTAssertEqual(streams.map(\.url.absoluteString), ["https://fixture.streamify.test/alpha", "https://fixture.streamify.test/bravo"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/matches/all", "/api/stream/alpha/fixture", "/api/stream/bravo/fixture"])
    }

    func testOneUnavailableProviderSourceDoesNotHideAnotherValidMatchedSource() async throws {
        let fixture = ProviderJSONFixture(.partialSourceClosure)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        let streams = try await service.streams(game)
        XCTAssertEqual(streams.map(\.url.absoluteString), ["https://fixture.streamify.test/bravo"])
    }

    func testAllMatchedSourceEndpointsReturningClosureKeepTheTypedError() async throws {
        let fixture = ProviderJSONFixture(.allSourcesClosure)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        do { _ = try await service.streams(game); XCTFail("No source was served.") }
        catch { guard case .streamProviderUnavailable? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
        XCTAssertEqual(fixture.requests.count, 3)
    }

    func testUnrelatedProviderGameNeverBecomesAReplacementForMissingSources() async throws {
        let fixture = ProviderJSONFixture(.unrelatedMatch)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        let streams = try await service.streams(game)
        XCTAssertTrue(streams.isEmpty)
        XCTAssertEqual(fixture.requests.count, 1, "Do not request a different game's player merely because the provider is unavailable.")
    }

    func testProviderTransportAndCancellationErrorsArePreserved() async throws {
        for code in [URLError.Code.notConnectedToInternet, .cancelled] {
            let fixture = ProviderJSONFixture(.failure(code))
            let service = SportsService(session: fixture.session, streamCatalog: .streamed)
            let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
            do { _ = try await service.streams(game); XCTFail("The request must fail.") }
            catch { XCTAssertEqual((error as? URLError)?.code, code, "Transport failures are not a provider closure.") }
        }
        let fixture = ProviderJSONFixture(.success)
        let service = SportsService(session: fixture.session, streamCatalog: .streamed)
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        let task = Task { try await service.streams(game) }
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled lookup must not start playback.") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }

    func testHTMLDetectionDoesNotChangeESPNParsingOrRejectValidJSONWithWrongMIMEType() throws {
        let provider = try XCTUnwrap(URL(string: "https://streamed.pk/api/matches/all"))
        let providerResponse = try XCTUnwrap(HTTPURLResponse(url: provider, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"]))
        XCTAssertNoThrow(try SportsService.validateJSONResponse(Data("[]".utf8), response: providerResponse, requestedURL: provider))
        let espn = try XCTUnwrap(URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"))
        let espnResponse = try XCTUnwrap(HTTPURLResponse(url: espn, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"]))
        XCTAssertThrowsError(try SportsService.validateJSONResponse(Data("<html>Unavailable</html>".utf8), response: espnResponse, requestedURL: espn)) {
            XCTAssertFalse($0 is SportsServiceError, "ESPN's parser behavior must remain unchanged.")
        }
    }

    func testWatchResolvesFreshSourceAddressesWhileKeepingDiscoveryResultsWarm() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamDiscoveryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        StreamDiscoveryProtocol.state.reset()
        let service = SportsService(session: session, streamCatalog: .streamed)
        var event = SportsFixture.event
        event["date"] = ISO8601DateFormatter().string(from: Date())
        let game = try XCTUnwrap(service.parseGame(event, league: .nba))
        let first = try await service.streams(game)
        let second = try await service.streams(game)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertNotEqual(first.first?.url, second.first?.url,
            "Another Watch must not reuse a source address from the previous connection.")
        XCTAssertEqual(StreamDiscoveryProtocol.state.calls, [1, 2],
            "Keep the match catalog cached, but fetch the selected stream's current address each time.")
    }
    func testESPNDecodesMixedScoreShapesAndShortUTCDate() throws {
        let service = SportsService()
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        XCTAssertEqual(game.id, "nba:fixture-game")
        XCTAssertEqual(game.home.name, "Boston Celtics")
        XCTAssertEqual(game.away.name, "Los Angeles Lakers")
        XCTAssertEqual(game.home.score, "115")
        XCTAssertEqual(game.away.score, "110")
        XCTAssertTrue(game.isLive)
        XCTAssertEqual(game.date, SportsService.parseDate("2026-10-23T00:30:00Z"))
        XCTAssertEqual(SportsService.parseDate("2026-10-23T00:30Z"), SportsService.parseDate("2026-10-22T20:30:00-04:00"))
        XCTAssertNotNil(SportsService.parseDate("2026-10-23T00:30:00.123Z"))
        XCTAssertNil(service.parseGame(["id": "bad", "competitions": []], league: .nba))
    }

    func testScheduleUsesSelectedLocalDayAndDeduplicatesAdjacentUTCFeeds() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SportsFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = SportsService(session: session, calendar: calendar)
        let result = try await service.schedule(leagues: [.nba], day: day)
        XCTAssertFalse(result.partial)
        XCTAssertEqual(result.games.map(\.eventID), ["fixture-game"], "00:30 UTC belongs to the previous Toronto day; duplicate UTC feeds must produce one card.")
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(result.games.first?.date), inSameDayAs: day))
    }

    func testStreamMatchRequiresBothFullTeamsRecentDateCorrectSportAndSources() throws {
        let game = try XCTUnwrap(SportsService().parseGame(SportsFixture.event, league: .nba))
        let now = try XCTUnwrap(SportsService.parseDate("2026-10-23T00:30:00Z"))
        func match(_ id: String, home: String = "Boston Celtics", away: String = "LA Lakers", category: String = "basketball", age: TimeInterval = 0, sources: Bool = true) -> [String: Any] {
            ["id": id, "title": "\(away) at \(home)", "category": category, "date": now.addingTimeInterval(-age).timeIntervalSince1970 * 1000,
             "teams": ["home": ["name": home], "away": ["name": away]], "sources": sources ? [["source": "alpha", "id": id]] : []]
        }
        let rejected = [match("wrong-sport", category: "hockey"), match("one-team", away: "Los Angeles Clippers"),
                        match("old", age: 48 * 3600), match("no-sources", sources: false)]
        XCTAssertNil(SportsService.matchingStreamMatch(rejected, game: game, now: now))
        let matched = try XCTUnwrap(SportsService.matchingStreamMatch(rejected + [match("correct")], game: game, now: now))
        XCTAssertEqual(matched["id"] as? String, "correct", "LA normalization must still require the full opponent.")
        let reversed = match("reversed", home: "Los Angeles Lakers", away: "Boston Celtics")
        XCTAssertEqual(SportsService.matchingStreamMatch([reversed], game: game, now: now)?["id"] as? String, "reversed")
    }

    func testDownloadAttemptIdentityRejectsLateCancelledAndRetriedCallbacks() throws {
        var item = DownloadItem(id: UUID(), title: "Fixture", source: "https://example.com/video.mp4", createdAt: Date(), status: .downloading)
        item.taskIdentifier = 17
        XCTAssertTrue(item.acceptsCallback(taskIdentifier: 17))
        item.status = .cancelled
        XCTAssertFalse(item.acceptsCallback(taskIdentifier: 17), "A finished file arriving after Cancel must not restore the cancelled entry.")
        item.status = .downloading
        item.taskIdentifier = 18
        XCTAssertFalse(item.acceptsCallback(taskIdentifier: 17), "A previous attempt must not overwrite the retried download.")
        XCTAssertTrue(item.acceptsCallback(taskIdentifier: 18))
        let restored = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
        XCTAssertTrue(restored.acceptsCallback(taskIdentifier: 18), "Background relaunches must retain the active task identity.")
        item.status = .completed
        XCTAssertFalse(item.acceptsCallback(taskIdentifier: 18))
    }
}

private enum SportsFixture {
    static var event: [String: Any] {
        ["id": "fixture-game", "date": "2026-10-23T00:30Z", "competitions": [[
            "status": ["type": ["state": "in", "shortDetail": "4th · 0:12"]],
            "venue": ["fullName": "Fixture Arena"], "broadcasts": [["names": ["ESPN"]]],
            "competitors": [
                ["homeAway": "home", "score": 115, "team": ["id": "2", "displayName": "Boston Celtics", "abbreviation": "BOS", "logo": "https://example.com/bos.png"]],
                ["homeAway": "away", "score": ["displayValue": "110"], "team": ["id": "13", "displayName": "Los Angeles Lakers", "abbreviation": "LAL", "logos": [["href": "https://example.com/lal.png"]]]]
            ]
        ]]]
    }
    static var scoreboard: Data {
        var nextDay = event
        nextDay["id"] = "next-local-day"
        nextDay["date"] = "2026-10-23T18:00Z"
        return (try? JSONSerialization.data(withJSONObject: ["events": [event, nextDay]])) ?? Data()
    }
}

private final class SportsFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "site.api.espn.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "/apis/site/v2/sports/basketball/nba/scoreboard",
              let date = parts.queryItems?.first(where: { $0.name == "dates" })?.value,
              ["20261021", "20261022", "20261023"].contains(date),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: SportsFixture.scoreboard)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class StreamDiscoveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var matches = 0
    private var sources = 0
    var calls: [Int] { lock.lock(); defer { lock.unlock() }; return [matches, sources] }
    func reset() { lock.lock(); defer { lock.unlock() }; matches = 0; sources = 0 }
    func data(for url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let object: [[String: Any]]
        if url.path == "/api/matches/all" {
            matches += 1
            object = [["id": "fixture", "title": "Los Angeles Lakers at Boston Celtics", "category": "basketball",
                "date": Date().timeIntervalSince1970 * 1000,
                "teams": ["home": ["name": "Boston Celtics"], "away": ["name": "Los Angeles Lakers"]],
                "sources": [["source": "alpha", "id": "fixture"]]]]
        } else {
            sources += 1
            object = [["embedUrl": "https://example.com/player?connection=\(sources)", "streamNo": 1, "language": "English", "hd": true]]
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

private final class StreamDiscoveryProtocol: URLProtocol {
    static let state = StreamDiscoveryState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "streamed.pk" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            let data = try Self.state.data(for: url)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class ProviderJSONFixture {
    enum Mode { case closureRedirect, closureHTML, invalidJSON, success, partialSourceClosure, allSourcesClosure, unrelatedMatch, failure(URLError.Code) }
    let session: URLSession
    private let identifier = UUID().uuidString
    private let scenario: ProviderJSONScenario
    var requests: [URLRequest] { scenario.requests }
    init(_ mode: Mode) {
        scenario = ProviderJSONScenario(mode)
        ProviderJSONProtocol.register(scenario, id: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderJSONProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Provider-Test": identifier]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); ProviderJSONProtocol.unregister(identifier) }
}

private final class ProviderJSONScenario {
    let mode: ProviderJSONFixture.Mode
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(_ mode: ProviderJSONFixture.Mode) { self.mode = mode }
    func record(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; recorded.append(request) }
    func response(for url: URL) throws -> (URL, String, Data) {
        let closure = Data("<!doctype html><html><head><title>Streamed Closure</title></head><body>We are no longer operating Streamed.<a href='https://ppv.st/'>Alternative</a></body></html>".utf8)
        switch mode {
        case .closureRedirect: return (URL(string: "https://streamed.pk/")!, "text/html; charset=utf-8", closure)
        case .closureHTML: return (url, "text/html; charset=utf-8", closure)
        case .invalidJSON: return (url, "application/json", Data("{\"broken\":".utf8))
        case .failure(let code): throw URLError(code)
        default: break
        }
        let object: [[String: Any]]
        if url.path == "/api/matches/all" {
            let opponent = if case .unrelatedMatch = mode { "Los Angeles Clippers" } else { "Los Angeles Lakers" }
            object = [["id": "fixture", "title": "\(opponent) at Boston Celtics", "category": "basketball", "date": Date().timeIntervalSince1970 * 1000,
                "teams": ["home": ["name": "Boston Celtics"], "away": ["name": opponent]],
                "sources": [["source": "alpha", "id": "fixture"], ["source": "bravo", "id": "fixture"]]]]
        } else {
            if case .allSourcesClosure = mode { return (URL(string: "https://streamed.pk/")!, "text/html", closure) }
            if case .partialSourceClosure = mode, url.path.contains("/alpha/") { return (url, "text/html", closure) }
            let source = url.path.contains("/bravo/") ? "bravo" : "alpha"
            object = [["embedUrl": "https://fixture.streamify.test/\(source)", "streamNo": 1, "language": "English", "hd": true]]
        }
        return (url, "application/json", try JSONSerialization.data(withJSONObject: object))
    }
}

private final class ProviderJSONProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: ProviderJSONScenario] = [:]
    static func register(_ scenario: ProviderJSONScenario, id: String) { lock.lock(); defer { lock.unlock() }; scenarios[id] = scenario }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-Streamify-Provider-Test").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        do {
            let scenario = try XCTUnwrap(scenario)
            scenario.record(request)
            let (url, type, data) = try scenario.response(for: XCTUnwrap(request.url))
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
