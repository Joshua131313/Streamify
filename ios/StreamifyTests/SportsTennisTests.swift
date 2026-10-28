import XCTest
@testable import Streamify

final class SportsTennisTests: XCTestCase {
    private let start = SportsService.parseDate("2026-10-28T14:30:00Z")!
    private func scoreboard(state: String = "in", timeKnown: Bool = true) -> [String: Any] {
        let away: [String: Any] = ["id": "11", "homeAway": "away", "winner": state == "post",
            "athlete": ["displayName": "Jannik Sinner", "shortName": "J. Sinner"],
            "linescores": [["value": 6, "winner": true], ["value": 2, "winner": false]]]
        let home: [String: Any] = ["id": "12", "homeAway": "home", "winner": false,
            "athlete": ["displayName": "Carlos Alcaraz", "shortName": "C. Alcaraz"],
            "linescores": [["value": 4, "winner": false], ["value": 6, "winner": true]]]
        return ["events": [["id": "10-2026", "name": "Vienna Open", "groupings": [["grouping": ["displayName": "Men's Singles"],
            "competitions": [["id": "185682", "date": "2026-10-28T14:30Z", "timeValid": timeKnown,
                "status": ["type": ["state": state, "detail": state == "post" ? "Retired" : "2nd Set"]],
                "competitors": [away, home], "round": ["displayName": "Round of 16"]]]]]]]]
    }

    func testNestedMatchesKeepCompetitionIdentitySetsAndExplicitRetirementWinner() throws {
        let game = try XCTUnwrap(SportsTennisFeed.parse(scoreboard(state: "post"), tour: .atp).first)
        XCTAssertEqual(game.eventID, "espn-atp-185682")
        XCTAssertEqual(game.date, start)
        XCTAssertEqual(game.tennis?.awaySets, ["6", "2"])
        XCTAssertEqual(game.tennis?.homeSets, ["4", "6"])
        XCTAssertEqual(game.winner?.name, "Jannik Sinner", "Equal completed sets must not erase an explicit retirement winner")
        XCTAssertEqual(game.tennis?.round, "Round of 16")
    }

    func testServingRequiresOneExplicitLiveCompetitorAndDoublesAreIdentified() throws {
        var raw = scoreboard()
        var tournament = raw.sportsObjects("events")[0]
        var grouping = tournament.sportsObjects("groupings")[0]
        var match = grouping.sportsObjects("competitions")[0]
        var players = match.sportsObjects("competitors")
        players[0]["possession"] = false; players[1]["possession"] = true
        match["competitors"] = players; grouping["competitions"] = [match]
        tournament["groupings"] = [grouping]; raw["events"] = [tournament]
        let live = try XCTUnwrap(SportsTennisFeed.parse(raw, tour: .atp).first)
        XCTAssertEqual(live.tennis?.servingID, live.home.id)
        XCTAssertFalse(live.tennis!.isDoubles)
        players[0]["possession"] = true; match["competitors"] = players
        grouping["grouping"] = ["displayName": "Men's Doubles"]
        grouping["competitions"] = [match]; tournament["groupings"] = [grouping]; raw["events"] = [tournament]
        let conflict = try XCTUnwrap(SportsTennisFeed.parse(raw, tour: .atp).first)
        XCTAssertNil(conflict.tennis?.servingID)
        XCTAssertTrue(conflict.tennis!.isDoubles)
    }

    func testCapturedMensikMatchLoadsPublishedChannelsWithoutGlobalCatalogue() async throws {
        let bundle = Bundle(for: Self.self)
        func fixture(_ name: String) throws -> Data {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json") ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
            return try Data(contentsOf: url)
        }
        let raw = try JSONSerialization.jsonObject(with: fixture("tennis-mensik-scoreboard")) as! [String: Any]
        let game = try XCTUnwrap(SportsTennisFeed.parse(raw, tour: .atp).first)
        let event = try fixture("tennis-mensik-matchora")
        let key = UUID().uuidString
        TennisSourceProtocol.register(key, data: event)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TennisSourceProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Tennis-Test": key]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); TennisSourceProtocol.remove(key) }
        let provider = MatchoraProvider(session: session, now: { game.date! })
        let sources = try await provider.streams(game)
        XCTAssertGreaterThan(sources.count, 3)
        XCTAssertTrue(sources.contains { $0.title.contains("TENNIS CHANNEL") })
        XCTAssertTrue(sources.allSatisfy { $0.url.host == "matchora.to" })
        XCTAssertEqual(TennisSourceProtocol.paths(key), ["/api/v1/events/es185185"])
    }

    func testTrackedPortraitsRemainInsideActivityPayloadBudget() throws {
        let attributes = SportsTrackedGameAttributes(league: "tennis", eventID: "espn-atp-185185",
            away: "A. Mannarino", home: "J. Mensik", awayID: "atp-1266", homeID: "atp-10319",
            awayName: "Adrian Mannarino", homeName: "Jakub Mensik", awayPortrait: Data(repeating: 1, count: 900), homePortrait: Data(repeating: 2, count: 900))
        let data = try JSONEncoder().encode(attributes)
        XCTAssertLessThan(data.count, 3300)
        XCTAssertEqual(try JSONDecoder().decode(SportsTrackedGameAttributes.self, from: data).homePortrait?.count, 900)
    }

    func testUnknownTimeAndMissingLivePointsStayUnknownAndTourIDsDoNotCollide() throws {
        let game = try XCTUnwrap(SportsTennisFeed.parse(scoreboard(state: "pre", timeKnown: false), tour: .atp).first)
        XCTAssertFalse(game.tennis!.timeConfirmed); XCTAssertFalse(game.canWatch)
        XCTAssertNil(game.tennis?.awayPoint); XCTAssertNil(game.tennis?.servingID)
        XCTAssertNotEqual(game.id, SportsTennisFeed.parse(scoreboard(), tour: .wta).first?.id)
        XCTAssertTrue(SportsTennisFeed.parse(["events": []], tour: .atp).isEmpty)
    }

    func testMatchoraRequiresExactESPNIdentityBothPlayersSportAndPublishedEmbed() throws {
        let game = try XCTUnwrap(SportsTennisFeed.parse(scoreboard(), tour: .atp).first)
        var event: [String: Any] = ["id": "es185682", "sport": "Tennis", "league": "ATP Vienna",
            "home": "Carlos Alcaraz", "away": "Jannik Sinner", "kickoff": start.timeIntervalSince1970]
        XCTAssertTrue(MatchoraProvider.matches(event, game: game, now: start))
        event["id"] = "es185683"; XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: start))
        event["id"] = "es185682"; event["away"] = "Other Player"
        XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: start))
        XCTAssertNotNil(MatchoraProvider.embed("https://matchora.to/embed/match/es185682", kind: "match", id: "es185682"))
        XCTAssertNil(MatchoraProvider.embed("https://matchora.to/embed/channel/es185682", kind: "channel", id: "es185682"))
        XCTAssertNil(MatchoraProvider.embed("https://matchora.to/embed/match/es185683", kind: "match", id: "es185682"))
    }

    private func challengerHTML() throws -> String {
        let bundle = Bundle(for: SportsTennisTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "tennis-challenger", withExtension: "html") ?? bundle.url(forResource: "tennis-challenger", withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    func testCapturedChallengerPairsIncludeSinglesDoublesAndTimezoneWithoutInventedLive() throws {
        let games = try SportsTennisExplorer.parse(challengerHTML())
        XCTAssertEqual(games.count, 3)
        let final = try XCTUnwrap(games.first { $0.eventID == "challenger-3361803" })
        XCTAssertEqual(final.date, SportsService.parseDate("2026-10-28T02:10:00Z"))
        XCTAssertEqual(final.winner?.name, "Jasika O.")
        XCTAssertEqual(final.tennis?.awaySets, ["6", "6"])
        let doubles = try XCTUnwrap(games.first { $0.eventID == "challenger-3358401" })
        XCTAssertEqual(doubles.away.name, "Reynolds F. / Watt J.")
        XCTAssertEqual(doubles.tennis?.discipline, "Men's Doubles")
        XCTAssertEqual(doubles.tennis?.awaySets, ["6", "3", "11"])
        XCTAssertTrue(games.contains { $0.state == "pre" }); XCTAssertFalse(games.contains(where: \.isLive))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        XCTAssertTrue(SportsScheduleDayPolicy.includes(final, on: SportsService.parseDate("2026-10-27T16:00Z")!, now: start, calendar: calendar))
    }
    func testChallengerRejectsUnpairedPlayersAndUnverifiedTournamentsOrInvalidDocument() throws {
        let html = try challengerHTML()
        XCTAssertEqual(try SportsTennisExplorer.parse(html.replacingOccurrences(of: "r312b", with: "r999b")).count, 2)
        XCTAssertTrue(try SportsTennisExplorer.parse(html.replacingOccurrences(of: "/seoul-challenger/", with: "/unrelated-tournament/")).isEmpty)
        XCTAssertThrowsError(try SportsTennisExplorer.parse("<html>Unavailable</html>"))
    }
    func testGroupingAndNavigationUseStableTourAndRequestedLeagueOrder() throws {
        let atp = SportsTennisFeed.parse(scoreboard(), tour: .atp), wta = SportsTennisFeed.parse(scoreboard(), tour: .wta)
        let groups = SportsTennisGroup.groups(try SportsTennisExplorer.parse(challengerHTML()) + wta + atp)
        XCTAssertEqual(Array(groups.prefix(3).map(\.tour)), [.atp, .wta, .challenger])
        XCTAssertEqual(SportsLeague.allCases, [.nhl, .nba, .wnba, .nfl, .ncaaf, .tennis, .mlb])
        XCTAssertTrue(SportsService.validTennisEventID("challenger-3361803"))
        XCTAssertFalse(SportsService.validTennisEventID("185682"))
        XCTAssertFalse(SportsService.validTennisEventID("espn-atp-../185682"))
    }
}

private final class TennisSourceProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: Data] = [:]
    private static var requests: [String: [String]] = [:]
    static func register(_ key: String, data: Data) { lock.lock(); defer { lock.unlock() }; fixtures[key] = data; requests[key] = [] }
    static func remove(_ key: String) { lock.lock(); defer { lock.unlock() }; fixtures.removeValue(forKey: key); requests.removeValue(forKey: key) }
    static func paths(_ key: String) -> [String] { lock.lock(); defer { lock.unlock() }; return requests[key] ?? [] }
    override class func canInit(with request: URLRequest) -> Bool { request.value(forHTTPHeaderField: "X-Tennis-Test") != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "X-Tennis-Test") ?? ""
        Self.lock.lock(); let data = Self.fixtures[key]; Self.requests[key, default: []].append(request.url!.path); Self.lock.unlock()
        guard let data, request.url?.path == "/api/v1/events/es185185" else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
