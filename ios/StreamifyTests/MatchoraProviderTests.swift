import XCTest
import Foundation
@testable import Streamify

/// Public API shapes captured from /schedule and /events/2601717. All traffic
/// below is intercepted locally; tests never contact a player or live provider.
final class MatchoraProviderTests: XCTestCase {
    func testCollegeDivisionLabelsRequireFootballRatherThanAnotherCollegeSport() {
        let game = MatchoraFixture.game(.ncaaf)
        var event = MatchoraFixture.event(.ncaaf)
        event["league"] = "NCAA Division 1 Football"
        XCTAssertTrue(MatchoraProvider.matches(event, game: game, now: MatchoraFixture.now))
        event["league"] = "NCAA Division 1"; event["sport"] = "American Football"
        XCTAssertTrue(MatchoraProvider.matches(event, game: game, now: MatchoraFixture.now))
        for sport in ["Basketball", "Soccer", "", "Football"] {
            event["sport"] = sport
            XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: MatchoraFixture.now))
        }
    }

    func testEveryLeagueRequiresBothOpponentsTheCorrectLeagueAndNearbyKickoff() {
        for league in SportsLeague.allCases where league != .tennis {
            let game = MatchoraFixture.game(league)
            let original = MatchoraFixture.event(league)
            XCTAssertTrue(MatchoraProvider.matches(original, game: game, now: MatchoraFixture.now))
            for (key, value) in [("home", "Unrelated Team"), ("away", game.home.name),
                                 ("league", league == .wnba ? "NBA" : "WNBA")] {
                var item = original; item[key] = value
                XCTAssertFalse(MatchoraProvider.matches(item, game: game, now: MatchoraFixture.now))
            }
            var old = original; old["kickoff"] = MatchoraFixture.start.addingTimeInterval(-86_400).timeIntervalSince1970
            XCTAssertFalse(MatchoraProvider.matches(old, game: game, now: MatchoraFixture.now))
            var finished = original; finished["finished"] = true
            XCTAssertFalse(MatchoraProvider.matches(finished, game: game, now: MatchoraFixture.now))
        }
    }

    func testMissingBoolMillisecondsAndUnsafeIDsCannotEnterTheEventURL() {
        let game = MatchoraFixture.game(.nba)
        let invalidDates: [Any] = [true, 0, -1, "1793143800", MatchoraFixture.start.timeIntervalSince1970 * 1000, NSNull()]
        for date in invalidDates {
            var event = MatchoraFixture.event(.nba); event["kickoff"] = date
            XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: MatchoraFixture.now))
        }
        let invalidIDs: [Any] = [true, 2601717, "", "../2601717", "2601717?other=1", "2601717/another", "2601717%2fother", String(repeating: "1", count: 19)]
        for id in invalidIDs {
            var event = MatchoraFixture.event(.nba); event["id"] = id
            XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: MatchoraFixture.now))
        }
    }

    func testEmbedURLsMustBePublishedExactFirstPartyPathsForTheirReturnedIdentity() {
        XCTAssertEqual(MatchoraProvider.embed("https://matchora.to/embed/channel/836356", kind: "channel", id: "836356")?.path, "/embed/channel/836356")
        for address in ["http://matchora.to/embed/channel/836356", "https://matchora.to.evil.example/embed/channel/836356",
            "https://example.test/embed/channel/836356", "https://user:secret@matchora.to/embed/channel/836356",
            "https://matchora.to:8443/embed/channel/836356", "https://matchora.to/embed/channel/836355",
            "https://matchora.to/embed/match/836356", "https://matchora.to/embed/channel/%38%33%36%33%35%36",
            "https://matchora.to/embed/channel/../836356", "https://matchora.to/embed/channel/836356?ch=other",
            "https://matchora.to/embed/channel/836356#other", "javascript:alert(1)"] {
            XCTAssertNil(MatchoraProvider.embed(address, kind: "channel", id: "836356"), address)
        }
    }

    func testEnglishAndPlayingChannelsSortFirstDeadAndDuplicateSourcesDropAndPublishedMatchIsLast() {
        var event = MatchoraFixture.event(.nba)
        event["channels"] = [MatchoraFixture.channel("1", language: "French", playing: true),
            MatchoraFixture.channel("2", language: "English", playing: false),
            MatchoraFixture.channel("3", language: "English", playing: true),
            MatchoraFixture.channel("3", language: "English", playing: true),
            MatchoraFixture.channel("4", language: "English", playing: true, dead: true)]
        let sources = MatchoraProvider.sources(event, game: MatchoraFixture.game(.nba))
        XCTAssertEqual(sources.map(\.url.path), ["/embed/channel/3", "/embed/channel/2", "/embed/channel/1", "/embed/match/2601717"])
        XCTAssertTrue(sources[2].title.contains("French"))
        XCTAssertEqual(sources.last?.title, "Matchora · Match player")
        XCTAssertEqual(Set(sources.map(\.id)).count, sources.count)
    }

    func testChannelChoicesAreBoundedAndDoNotInventMissingMatchOrChannelEmbeds() {
        var event = MatchoraFixture.event(.nba)
        event["channels"] = (1...24).map { MatchoraFixture.channel(String($0)) }
        XCTAssertEqual(MatchoraProvider.sources(event, game: MatchoraFixture.game(.nba)).count, 11)
        event.removeValue(forKey: "embed_url")
        XCTAssertEqual(MatchoraProvider.sources(event, game: MatchoraFixture.game(.nba)).count, 10)
        event["channels"] = [["id": "836356", "name": "NBA"]]
        XCTAssertTrue(MatchoraProvider.sources(event, game: MatchoraFixture.game(.nba)).isEmpty)
        event["channels"] = []; event["channel_count"] = 0
        event["embed_url"] = "https://matchora.to/embed/match/2601717"
        XCTAssertTrue(MatchoraProvider.sources(event, game: MatchoraFixture.game(.nba)).isEmpty)
    }

    func testCapturedNBAAndNHLTopLevelEventShapesResolveOnlyReturnedChannelsAndMatch() async throws {
        for league in [SportsLeague.nba, .nhl] {
            let fixture = MatchoraHTTPFixture(.success, league: league)
            let values = try await MatchoraProvider(session: fixture.session, now: { MatchoraFixture.now }).streams(MatchoraFixture.game(league))
            XCTAssertEqual(values.count, 3)
            XCTAssertEqual(values.first?.url.absoluteString, "https://matchora.to/embed/channel/836356")
            XCTAssertEqual(values.last?.url.absoluteString, "https://matchora.to/embed/match/2601717")
            XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/v1/schedule", "/api/v1/events/2601717"])
            XCTAssertEqual(fixture.requests.first?.url?.query, "watchable=1")
        }
    }

    func testWarmCatalogStillRefreshesEventAndItsCurrentChannelsOnEveryWatch() async throws {
        let fixture = MatchoraHTTPFixture(.changing)
        let provider = MatchoraProvider(session: fixture.session, now: { MatchoraFixture.now })
        let first = try await provider.streams(MatchoraFixture.game(.nba))
        let second = try await provider.streams(MatchoraFixture.game(.nba))
        XCTAssertEqual(first.first?.url.lastPathComponent, "836356")
        XCTAssertEqual(second.first?.url.lastPathComponent, "90939")
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/v1/schedule", "/api/v1/events/2601717", "/api/v1/events/2601717"])
    }

    func testUnmatchedScheduleNeverGuessesAnEventOrEmbed() async throws {
        let fixture = MatchoraHTTPFixture(.unrelated)
        let values = try await MatchoraProvider(session: fixture.session, now: { MatchoraFixture.now }).streams(MatchoraFixture.game(.nba))
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testRefreshedEventMustRetainItsIDLeagueOpponentsAndDate() async throws {
        for mutation in ["id", "league", "home", "away", "kickoff"] {
            let fixture = MatchoraHTTPFixture(.changedIdentity(mutation))
            do {
                _ = try await MatchoraProvider(session: fixture.session, now: { MatchoraFixture.now }).streams(MatchoraFixture.game(.nba))
                XCTFail("Refreshed wrong \(mutation) must be rejected")
            } catch { guard case .invalidResponse? = error as? SportsServiceError else { return XCTFail("Unexpected \(error)") } }
        }
    }

    func testDeniedAndHTMLResponsesAreNotCachedAsUsableChannels() async throws {
        for mode in [MatchoraHTTPFixture.Mode.denied, .html] {
            let fixture = MatchoraHTTPFixture(mode)
            do {
                _ = try await MatchoraProvider(session: fixture.session, now: { MatchoraFixture.now }).streams(MatchoraFixture.game(.nba))
                XCTFail("A denied/HTML response cannot become an embed")
            } catch {
                if case .denied = mode { guard case .unavailable(403)? = error as? SportsServiceError else { return XCTFail("Unexpected \(error)") } }
                else { guard case .streamProviderUnavailable? = error as? SportsServiceError else { return XCTFail("Unexpected \(error)") } }
            }
        }
    }

    func testCancellationStopsTheOwnedLookupWithoutOpeningAPlayer() async throws {
        let fixture = MatchoraHTTPFixture(.pending)
        let task = Task { try await MatchoraProvider(session: fixture.session, now: { MatchoraFixture.now }).streams(MatchoraFixture.game(.nba)) }
        await fulfillment(of: [fixture.started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled lookup must not return sources") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [fixture.stopped], timeout: 2)
        XCTAssertEqual(fixture.requests.count, 1)
    }
}

private enum MatchoraFixture {
    static let start = Date(timeIntervalSince1970: 1_793_143_800)
    static let now = start.addingTimeInterval(1200)
    static func game(_ league: SportsLeague) -> SportsGame {
        let names: (String, String)
        switch league {
        case .nba: names = ("Boston Celtics", "Brooklyn Nets")
        case .nhl: names = ("Philadelphia Flyers", "Columbus Blue Jackets")
        case .nfl: names = ("Dallas Cowboys", "Philadelphia Eagles")
        case .ncaaf: names = ("Georgia Bulldogs", "Alabama Crimson Tide")
        case .mlb: names = ("New York Yankees", "Los Angeles Dodgers")
        case .tennis: names = ("Jannik Sinner", "Carlos Alcaraz")
        case .wnba: names = ("New York Liberty", "Las Vegas Aces")
        }
        return SportsGame(eventID: "401909876", league: league, date: start, state: "in", status: "Live",
            home: SportsTeam(id: "home", name: names.0, abbreviation: "HOME", logo: ""),
            away: SportsTeam(id: "away", name: names.1, abbreviation: "AWAY", logo: ""), venue: "", broadcasts: "", link: "")
    }
    static func channel(_ id: String, language: String = "English", playing: Bool = true, dead: Bool = false) -> [String: Any] {
        ["id": id, "name": "Channel \(id)", "lang": language, "playing": playing, "dead": dead,
         "embed_url": "https://matchora.to/embed/channel/\(id)"]
    }
    static func event(_ league: SportsLeague) -> [String: Any] {
        let game = game(league)
        return ["id": "2601717", "home": game.home.name, "away": game.away.name, "league": league.title,
            "kickoff": start.timeIntervalSince1970, "live": true, "finished": false, "channel_count": 2,
            "embed_url": "https://matchora.to/embed/match/2601717", "channels": [channel("836356"), channel("836355")]]
    }
}

private final class MatchoraHTTPFixture {
    enum Mode { case success, changing, unrelated, changedIdentity(String), denied, html, pending }
    let session: URLSession
    private let id = UUID().uuidString
    private let scenario: MatchoraScenario
    var requests: [URLRequest] { scenario.requests }
    var started: XCTestExpectation { scenario.started }
    var stopped: XCTestExpectation { scenario.stopped }
    init(_ mode: Mode, league: SportsLeague = .nba) {
        scenario = MatchoraScenario(mode, league: league)
        MatchoraProtocol.register(scenario, id: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MatchoraProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Matchora-Test": id]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); MatchoraProtocol.unregister(id) }
}

private final class MatchoraScenario {
    let mode: MatchoraHTTPFixture.Mode
    let league: SportsLeague
    let started = XCTestExpectation(description: "Matchora lookup started")
    let stopped = XCTestExpectation(description: "Matchora lookup cancelled")
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var eventCalls = 0
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(_ mode: MatchoraHTTPFixture.Mode, league: SportsLeague) { self.mode = mode; self.league = league }
    func response(_ request: URLRequest) throws -> (Int, Data)? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let url = try XCTUnwrap(request.url)
        guard url.host == "matchora.to", url.scheme == "https" else { throw URLError(.unsupportedURL) }
        if case .denied = mode { return (403, Data("{}".utf8)) }
        if case .html = mode { return (200, Data("<html>Unavailable</html>".utf8)) }
        var event = MatchoraFixture.event(league)
        let object: [String: Any]
        if url.path == "/api/v1/schedule" {
            if case .pending = mode { started.fulfill(); return nil }
            if case .unrelated = mode { event["home"] = "Other Team" }
            object = ["events": [event]]
        } else if url.path == "/api/v1/events/2601717" {
            eventCalls += 1
            if case .changing = mode, eventCalls > 1 { event["channels"] = [MatchoraFixture.channel("90939")] }
            if case .changedIdentity(let key) = mode {
                if key == "kickoff" { event[key] = MatchoraFixture.start.addingTimeInterval(-86_400).timeIntervalSince1970 }
                else { event[key] = "999999" }
            }
            object = event
        } else { throw URLError(.unsupportedURL) }
        return (200, try JSONSerialization.data(withJSONObject: object))
    }
    func stop() { if case .pending = mode { stopped.fulfill() } }
}

private final class MatchoraProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: MatchoraScenario] = [:]
    private var scenario: MatchoraScenario?
    static func register(_ scenario: MatchoraScenario, id: String) { lock.lock(); defer { lock.unlock() }; scenarios[id] = scenario }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); scenario = request.value(forHTTPHeaderField: "X-Streamify-Matchora-Test").flatMap { Self.scenarios[$0] }; Self.lock.unlock()
        do {
            guard let (status, data) = try XCTUnwrap(scenario).response(request) else { return }
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { scenario?.stop() }
}
