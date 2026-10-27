import Foundation
import XCTest
@testable import Streamify

/// Public response-shaped snapshots and URLProtocol only. No provider, player,
/// Firebase, authentication or media request reaches the network.
final class SportsStreamProviderTests: XCTestCase {
    func testDefaultUsesOfficialComAPIAndRefreshesWatchWithoutCachingItsSourceURL() async throws {
        let fixture = TimProviderProtocolFixture(.success)
        let service = SportsService(session: fixture.session, streamCatalog: .timStreams)
        let first = try await service.streams(TimProviderSnapshots.nbaGame)
        let second = try await service.streams(TimProviderSnapshots.nbaGame)
        XCTAssertEqual(first.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertEqual(second.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-2"])
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "tim-streams.com", "tim-streams.com"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug, "/api/watch/" + TimProviderSnapshots.nbaSlug])
    }

    func testPrimaryCannotFindHostUsesTheOtherOfficialCatalogAndWatchOnTheSameHost() async throws {
        let fixture = TimProviderProtocolFixture(.primaryDNSFailure)
        let values = try await SportsService(session: fixture.session, streamCatalog: .timStreams).streams(TimProviderSnapshots.nbaGame)
        XCTAssertEqual(values.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "timst.top", "timst.top"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug])
    }

    func testWatchHostFailureReloadsTheOtherHostsCatalogInsteadOfMixingKeys() async throws {
        let fixture = TimProviderProtocolFixture(.primaryWatchDNSFailure)
        let values = try await SportsService(session: fixture.session, streamCatalog: .timStreams).streams(TimProviderSnapshots.nbaGame)
        XCTAssertEqual(values.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "tim-streams.com", "timst.top", "timst.top"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug,
            "/api/live-upcoming", "/api/watch/returned-by-top-" + TimProviderSnapshots.nbaGame.eventID])
    }

    func testPrimaryHTMLFailureCanUseTheOfficialAlternateWithoutRawParseErrors() async throws {
        let fixture = TimProviderProtocolFixture(.primaryClosure)
        let values = try await SportsService(session: fixture.session, streamCatalog: .timStreams).streams(TimProviderSnapshots.nbaGame)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "timst.top", "timst.top"])
    }

    func testBothHostDNSFailuresPreserveTheMeaningfulTransportError() async throws {
        let fixture = TimProviderProtocolFixture(.bothDNSFailure)
        do { _ = try await SportsService(session: fixture.session, streamCatalog: .timStreams).streams(TimProviderSnapshots.nbaGame); XCTFail("Both API hosts are unavailable.") }
        catch { XCTAssertEqual((error as? URLError)?.code, .cannotFindHost) }
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "timst.top"])
    }

    func testCancelledPrimaryDoesNotStartAHostFailoverOrAPlayer() async throws {
        let fixture = TimProviderProtocolFixture(.primaryCancellation)
        do { _ = try await SportsService(session: fixture.session, streamCatalog: .timStreams).streams(TimProviderSnapshots.nbaGame); XCTFail("Cancellation must stop discovery.") }
        catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com"])
    }

    func testHangingPrimaryCatalogIsCancelledAndAlternateFinishesWithinAggregateBudget() async throws {
        let fixture = TimProviderProtocolFixture(.primaryDelayedCatalog)
        let service = SportsService(session: fixture.session, streamCatalog: .timStreams)
        let began = Date()
        let values = try await SportsService.withSourceDeadline(seconds: 6) {
            try await service.streams(TimProviderSnapshots.nbaGame)
        }
        XCTAssertEqual(values.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertLessThan(Date().timeIntervalSince(began), 5.5)
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "timst.top", "timst.top"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug])
        for _ in 0..<100 where !fixture.stoppedRequests.contains(where: { $0.url?.host == "tim-streams.com" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.stoppedRequests.contains { $0.url?.host == "tim-streams.com" && $0.url?.path == "/api/live-upcoming" },
            "The expired catalog must cancel its actual URLSession transport.")
    }

    func testCatalogAndWatchShareOneHostBudgetInsteadOfReceivingThreeSecondsEach() async throws {
        let fixture = TimProviderProtocolFixture(.primaryPairedDelay)
        let service = SportsService(session: fixture.session, streamCatalog: .timStreams)
        let began = Date()
        let values = try await SportsService.withSourceDeadline(seconds: 6) {
            try await service.streams(TimProviderSnapshots.nbaGame)
        }
        XCTAssertEqual(values.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertLessThan(Date().timeIntervalSince(began), 5.5)
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com", "tim-streams.com", "timst.top", "timst.top"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug,
            "/api/live-upcoming", "/api/watch/returned-by-top-" + TimProviderSnapshots.nbaGame.eventID])
        for _ in 0..<100 where !fixture.stoppedRequests.contains(where: { $0.url?.host == "tim-streams.com" && $0.url?.path.hasPrefix("/api/watch/") == true }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.stoppedRequests.contains { $0.url?.host == "tim-streams.com" && $0.url?.path.hasPrefix("/api/watch/") == true })
    }

    func testCancellingAHangingPrimaryCancelsTransportWithoutStartingAlternate() async throws {
        let fixture = TimProviderProtocolFixture(.primaryDelayedCatalog)
        let service = SportsService(session: fixture.session, streamCatalog: .timStreams)
        let lookup = Task { try await service.streams(TimProviderSnapshots.nbaGame) }
        for _ in 0..<100 where fixture.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(fixture.requests.isEmpty, "Cancel an actual active request, not an unstarted lookup.")
        lookup.cancel()
        do { _ = try await lookup.value; XCTFail("Cancelled discovery cannot return a player.") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        for _ in 0..<100 where fixture.stoppedRequests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com"])
        XCTAssertTrue(fixture.stoppedRequests.contains { $0.url?.host == "tim-streams.com" })
    }

    func testAValidCatalogWithoutThisEventDoesNotGuessOtherHostsOrSources() async throws {
        let fixture = TimProviderProtocolFixture(.unrelatedCatalog)
        let values = try await SportsService(session: fixture.session, streamCatalog: .timStreams).streams(TimProviderSnapshots.nbaGame)
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(fixture.requests.map { $0.url?.host }, ["tim-streams.com"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming"])
    }

    func testCapturedNBAAndNHLItemsKeepTheProvidersActualSourceAddresses() throws {
        let nba = try decoded(TimProviderSnapshots.nba)
        let nhl = try decoded(TimProviderSnapshots.nhl)
        let basketball = SportsService.timstStreams(nba, game: TimProviderSnapshots.nbaGame)
        let hockey = SportsService.timstStreams(nhl, game: TimProviderSnapshots.nhlGame)
        XCTAssertEqual(basketball.map(\.url.absoluteString), ["https://ehgembxe.cfd/iq18ya3a-1439"])
        XCTAssertEqual(basketball.map(\.title), ["TimStreams · NBA League Pass"])
        XCTAssertEqual(hockey.map(\.url.absoluteString), ["https://ehgembxe.cfd/so0owb39-7675"])
        XCTAssertEqual(hockey.map(\.title), ["TimStreams · ESPN+"])
    }

    func testExactEventIdentityAcceptsNFLNicknamesAndTheCollegeFootballGenre() {
        let cases: [(SportsLeague, Int, String, String)] = [
            (.nfl, 8, "401873009", "Cowboys @ Eagles"),
            (.ncaaf, 8, "401873010", "Alabama @ Georgia"),
            (.wnba, 7, "401873011", "Liberty @ Aces"),
            (.mlb, 9, "401908044", "Brewers @ Rays")
        ]
        for (league, genre, id, name) in cases {
            let game = TimProviderSnapshots.game(league, id: id)
            let raw = TimProviderSnapshots.item(game, genre: genre, name: name)
            XCTAssertEqual(SportsService.timstStreams(raw, game: game).count, 1,
                           "An exact ESPN event ID must not require the provider to spell out both city names: \(league)")
        }
    }

    func testSameTeamsOrBasketballGenreNeverSubstituteForADifferentEventIdentity() throws {
        let nba = TimProviderSnapshots.nbaGame
        var raw = try decoded(TimProviderSnapshots.nba)
        raw["url"] = "golden-state-warriors-v-denver-nuggets-401909875"
        XCTAssertTrue(SportsService.timstStreams(raw, game: nba).isEmpty, "The right teams from a different game are insufficient.")
        raw = try decoded(TimProviderSnapshots.nba)
        let wnba = TimProviderSnapshots.game(.wnba, id: "401873011")
        XCTAssertTrue(SportsService.timstStreams(raw, game: wnba).isEmpty, "NBA and WNBA share a genre, never an event identity.")
        raw["url"] = "golden-state-warriors-v-denver-nuggets-4019098760"
        XCTAssertTrue(SportsService.timstStreams(raw, game: nba).isEmpty, "ID matching must include the complete suffix boundary.")
        raw["url"] = "golden-state-warriors-v-denver-nuggets-401909876-backup"
        XCTAssertTrue(SportsService.timstStreams(raw, game: nba).isEmpty)
    }

    func testCorrectIdentityStillRequiresTheCorrectSportAndAFreeEvent() throws {
        let game = TimProviderSnapshots.nbaGame
        let original = try decoded(TimProviderSnapshots.nba)
        for genre in [8, 9, 11] {
            var raw = original; raw["genre"] = genre
            XCTAssertTrue(SportsService.timstStreams(raw, game: game).isEmpty, "Wrong sport genre \(genre).")
        }
        var vip = original; vip["vip"] = true
        XCTAssertTrue(SportsService.timstStreams(vip, game: game).isEmpty)
        var channel = original; channel["isevent"] = false
        XCTAssertTrue(SportsService.timstStreams(channel, game: game).isEmpty, "A 24/7 channel is not the requested game.")
    }

    func testMalformedRecordsAndAbsentIdentityFlagsNeverProduceAGuessedPlayer() throws {
        let game = TimProviderSnapshots.nbaGame
        let original = try decoded(TimProviderSnapshots.nba)
        for field in ["url", "genre", "isevent", "vip"] {
            var raw = original; raw.removeValue(forKey: field)
            XCTAssertTrue(SportsService.timstStreams(raw, game: game).isEmpty, "Missing \(field) must fail closed.")
        }
        let malformedURLs: [Any] = ["", "no-event-id", 401909876, NSNull()]
        for badURL in malformedURLs {
            var raw = original; raw["url"] = badURL
            XCTAssertTrue(SportsService.timstStreams(raw, game: game).isEmpty)
        }
        var malformed = original; malformed["streams"] = "not an array"
        XCTAssertTrue(SportsService.timstStreams(malformed, game: game).isEmpty)
        XCTAssertTrue(SportsService.timstStreams([:], game: game).isEmpty)
    }

    func testOnlyFreeHTTPSCredentialFreeSourcesRemainAndDuplicatesKeepReturnedOrder() throws {
        var raw = try decoded(TimProviderSnapshots.nba)
        let exact = "https://fixture.streamify.test/player/one?key=a%2Fb&quality=hd"
        let sources: [[String: Any]] = [
            ["name": "Paid", "url": "https://fixture.streamify.test/paid", "vip": true],
            ["name": "Main", "url": exact, "vip": false],
            ["name": "Duplicate", "url": exact, "vip": false],
            ["name": "HTTP", "url": "http://fixture.streamify.test/plain", "vip": false],
            ["name": "Credentials", "url": "https://user:secret@fixture.streamify.test/player", "vip": false],
            ["name": "Relative", "url": "/embed/guessed", "vip": false],
            ["name": "Script", "url": "javascript:alert(1)", "vip": false],
            ["name": "Empty", "url": "", "vip": false],
            ["name": "Missing host", "url": "https://", "vip": false],
            ["name": "Alternate", "url": "https://fixture.streamify.test/player/two", "vip": false]
        ]
        raw["streams"] = sources
        let values = SportsService.timstStreams(raw, game: TimProviderSnapshots.nbaGame)
        XCTAssertEqual(values.map(\.url.absoluteString), [exact, "https://fixture.streamify.test/player/two"])
        XCTAssertEqual(values.map(\.title), ["TimStreams · Main", "TimStreams · Alternate"])
    }

    func testNoSourcesNeverConstructsAnEmbedFromTheEventSlug() throws {
        let original = try decoded(TimProviderSnapshots.nba)
        let incompleteSource: [[String: Any]] = [["name": "Missing URL", "vip": false]]
        let missingSources: [Any] = [[[String: Any]](), NSNull(), incompleteSource]
        for sources in missingSources {
            var raw = original; raw["streams"] = sources
            XCTAssertTrue(SportsService.timstStreams(raw, game: TimProviderSnapshots.nbaGame).isEmpty)
        }
        var absent = original; absent.removeValue(forKey: "streams")
        XCTAssertTrue(SportsService.timstStreams(absent, game: TimProviderSnapshots.nbaGame).isEmpty)
    }

    func testExplicitTimHostUsesTheReturnedCatalogSlugThenTheFreshWatchItem() async throws {
        let fixture = TimProviderProtocolFixture(.success)
        let values = try await SportsService(session: fixture.session, streamCatalog: .timStreams, timStreamAPIHosts: ["timst.top"]).streams(TimProviderSnapshots.nbaGame)
        XCTAssertEqual(values.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug])
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.scheme == "https" && $0.url?.host == "timst.top" })
    }

    func testAnotherWatchRefreshesItsAddressWhileTheCatalogRemainsWarm() async throws {
        let fixture = TimProviderProtocolFixture(.success)
        let service = SportsService(session: fixture.session, streamCatalog: .timStreams, timStreamAPIHosts: ["timst.top"])
        let first = try await service.streams(TimProviderSnapshots.nbaGame)
        let second = try await service.streams(TimProviderSnapshots.nbaGame)
        XCTAssertEqual(first.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-1"])
        XCTAssertEqual(second.map(\.url.absoluteString), ["https://fixture.streamify.test/fresh-2"])
        XCTAssertEqual(fixture.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug, "/api/watch/" + TimProviderSnapshots.nbaSlug])
    }

    func testUnrelatedCatalogAndWrongWatchItemAreRejectedWithoutGuessingOrFallback() async throws {
        let unrelated = TimProviderProtocolFixture(.unrelatedCatalog)
        let values = try await SportsService(session: unrelated.session, streamCatalog: .timStreams, timStreamAPIHosts: ["timst.top"]).streams(TimProviderSnapshots.nbaGame)
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(unrelated.requests.map { $0.url?.path }, ["/api/live-upcoming"], "Do not derive a watch URL from team names or an ESPN ID.")
        let changed = TimProviderProtocolFixture(.wrongWatchItem)
        do { _ = try await SportsService(session: changed.session, streamCatalog: .timStreams, timStreamAPIHosts: ["timst.top"]).streams(TimProviderSnapshots.nbaGame); XCTFail("An unrelated watch item must not become playback.") }
        catch { guard case .invalidResponse? = error as? SportsServiceError else { return XCTFail("Unexpected rejection: \(error)") } }
        XCTAssertEqual(changed.requests.map { $0.url?.path }, ["/api/live-upcoming", "/api/watch/" + TimProviderSnapshots.nbaSlug])
        XCTAssertTrue((unrelated.requests + changed.requests).allSatisfy { $0.url?.host == "timst.top" }, "A missing event must not silently fall back to the dead provider.")
    }

    func testProviderFailureAndCancellationArePreservedWithoutFetchingOtherHosts() async throws {
        for mode in [TimProviderProtocolFixture.Mode.catalogFailure(.cannotConnectToHost), .watchFailure(.notConnectedToInternet), .watchFailure(.cancelled)] {
            let fixture = TimProviderProtocolFixture(mode)
            do { _ = try await SportsService(session: fixture.session, streamCatalog: .timStreams, timStreamAPIHosts: ["timst.top"]).streams(TimProviderSnapshots.nbaGame); XCTFail("The provider request must report its failure.") }
            catch { XCTAssertEqual((error as? URLError)?.code, mode.failureCode) }
            XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "timst.top" })
        }
    }

    func testCancelledLookupCannotReturnAPlayerSource() async throws {
        let fixture = TimProviderProtocolFixture(.success)
        let service = SportsService(session: fixture.session, streamCatalog: .timStreams, timStreamAPIHosts: ["timst.top"])
        let task = Task { try await service.streams(TimProviderSnapshots.nbaGame) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must prevent handing a source to playback.") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "timst.top" })
    }

    private func decoded(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}

private enum TimProviderSnapshots {
    static let nbaSlug = "golden-state-warriors-v-denver-nuggets-401909876"
    static let nba = """
    {"url":"golden-state-warriors-v-denver-nuggets-401909876","name":"Golden State Warriors @ Denver Nuggets","genre":7,"sub_genre":1,"time":"2026-10-26T22:00","isevent":true,"vip":false,"streams":[{"name":"NBA League Pass","url":"https://ehgembxe.cfd/iq18ya3a-1439","vip":false}]}
    """
    static let nhl = """
    {"url":"toronto-maple-leafs-v-calgary-flames-401892583","name":"Toronto Maple Leafs @ Calgary Flames","genre":11,"time":"2026-10-26T20:30","isevent":true,"vip":false,"streams":[{"name":"ESPN+","url":"https://ehgembxe.cfd/so0owb39-7675","vip":false}]}
    """
    static var nbaGame: SportsGame { game(.nba, id: "401909876", home: "Denver Nuggets", away: "Golden State Warriors") }
    static var nhlGame: SportsGame { game(.nhl, id: "401892583", home: "Calgary Flames", away: "Toronto Maple Leafs") }
    static func game(_ league: SportsLeague, id: String, home: String = "Home Team", away: String = "Away Team") -> SportsGame {
        SportsGame(eventID: id, league: league, date: Date(), state: "in", status: "Live",
                   home: SportsTeam(id: "h", name: home, abbreviation: "HOME", logo: ""),
                   away: SportsTeam(id: "a", name: away, abbreviation: "AWAY", logo: ""), venue: "", broadcasts: "", link: "")
    }
    static func item(_ game: SportsGame, genre: Int = 7, name: String = "Golden State Warriors @ Denver Nuggets", source: String = "https://fixture.streamify.test/catalog-address") -> [String: Any] {
        ["url": game.eventID == "401909876" ? nbaSlug : "returned-event-" + game.eventID,
         "name": name, "genre": genre, "isevent": true, "vip": false,
         "streams": [["name": "Fixture source", "url": source, "vip": false]]]
    }
}

private final class TimProviderProtocolFixture {
    enum Mode {
        case success, unrelatedCatalog, wrongWatchItem, catalogFailure(URLError.Code), watchFailure(URLError.Code)
        case primaryDNSFailure, primaryWatchDNSFailure, primaryClosure, bothDNSFailure, primaryCancellation
        case primaryDelayedCatalog, primaryPairedDelay
        var failureCode: URLError.Code? { switch self { case .catalogFailure(let code), .watchFailure(let code): return code; default: return nil } }
    }
    let session: URLSession
    private let identifier = UUID().uuidString
    private let scenario: TimProviderProtocolScenario
    var requests: [URLRequest] { scenario.requests }
    var stoppedRequests: [URLRequest] { scenario.stoppedRequests }
    init(_ mode: Mode) {
        scenario = TimProviderProtocolScenario(mode)
        TimProviderURLProtocol.register(scenario, id: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimProviderURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Tim-Test": identifier]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); TimProviderURLProtocol.unregister(identifier) }
}

private final class TimProviderProtocolScenario {
    let mode: TimProviderProtocolFixture.Mode
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var stopped: [URLRequest] = []
    private var watches = 0
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    var stoppedRequests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stopped }
    init(_ mode: TimProviderProtocolFixture.Mode) { self.mode = mode }
    func began(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; recorded.append(request) }
    func cancelled(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; stopped.append(request) }
    func delay(for request: URLRequest) -> TimeInterval {
        guard request.url?.host == "tim-streams.com" else { return 0 }
        if case .primaryDelayedCatalog = mode, request.url?.path == "/api/live-upcoming" { return 10 }
        if case .primaryPairedDelay = mode { return 1.7 }
        return 0
    }
    func response(_ request: URLRequest) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let url = try XCTUnwrap(request.url)
        guard ["tim-streams.com", "timst.top"].contains(url.host ?? ""), url.scheme == "https" else { throw URLError(.unsupportedURL) }
        if case .bothDNSFailure = mode { throw URLError(.cannotFindHost) }
        if url.host == "tim-streams.com" {
            if case .primaryDNSFailure = mode { throw URLError(.cannotFindHost) }
            if case .primaryCancellation = mode { throw URLError(.cancelled) }
            if case .primaryClosure = mode { return Data("<!doctype html><html><title>API unavailable</title></html>".utf8) }
        }
        var expectedSlug = TimProviderSnapshots.nbaSlug
        let differentMirrorKey: Bool
        switch mode { case .primaryWatchDNSFailure, .primaryPairedDelay: differentMirrorKey = true; default: differentMirrorKey = false }
        if differentMirrorKey, url.host == "timst.top" {
            expectedSlug = "returned-by-top-" + TimProviderSnapshots.nbaGame.eventID
        }
        let object: [String: Any]
        if url.path == "/api/live-upcoming" {
            if case .catalogFailure(let code) = mode { throw URLError(code) }
            var event = TimProviderSnapshots.item(TimProviderSnapshots.nbaGame)
            event["url"] = expectedSlug
            if case .unrelatedCatalog = mode { event["url"] = "other-event-401909875" }
            object = ["events": [event], "genres": [["id": 7, "name": "Basketball"]]]
        } else if url.path == "/api/watch/" + expectedSlug {
            if case .primaryWatchDNSFailure = mode, url.host == "tim-streams.com" { throw URLError(.cannotFindHost) }
            if case .watchFailure(let code) = mode { throw URLError(code) }
            watches += 1
            var item = TimProviderSnapshots.item(TimProviderSnapshots.nbaGame, source: "https://fixture.streamify.test/fresh-\(watches)")
            item["url"] = expectedSlug
            if case .wrongWatchItem = mode { item["url"] = "unrelated-game-401909875" }
            object = ["item": item, "genre_name": "Basketball", "type": "event", "is_vip_user": false]
        } else { throw URLError(.unsupportedURL) }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

private final class TimProviderURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: TimProviderProtocolScenario] = [:]
    private let stateLock = NSLock()
    private var pending: DispatchWorkItem?
    private var cancelled = false
    private var activeScenario: TimProviderProtocolScenario?
    static func register(_ value: TimProviderProtocolScenario, id: String) { lock.lock(); defer { lock.unlock() }; scenarios[id] = value }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-Streamify-Tim-Test").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        guard let scenario else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        stateLock.lock(); activeScenario = scenario; stateLock.unlock()
        scenario.began(request)
        let delay = scenario.delay(for: request)
        if delay > 0 {
            let item = DispatchWorkItem { [weak self] in self?.deliver(scenario) }
            stateLock.lock(); pending = item; let shouldSchedule = !cancelled; stateLock.unlock()
            if shouldSchedule { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item) }
        } else { deliver(scenario) }
    }
    private func deliver(_ fixture: TimProviderProtocolScenario) {
        stateLock.lock(); let stopped = cancelled; pending = nil; stateLock.unlock()
        guard !stopped else { return }
        do {
            let data = try fixture.response(request)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {
        stateLock.lock(); cancelled = true; let item = pending; pending = nil; let scenario = activeScenario; stateLock.unlock()
        item?.cancel()
        scenario?.cancelled(request)
    }
}
