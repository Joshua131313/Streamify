import Foundation
import XCTest
@testable import Streamify

final class SportsLiveSituationTests: XCTestCase {
    func testFootballProgressUsesOffenseAndExplicitFieldSideRatherThanRawYardLine() throws {
        let service = SportsService()
        let awayBall = try XCTUnwrap(service.parseGame(Self.event(situation: [
            "possession": "19", "possessionText": "HOU 48", "yardLine": 48,
            "shortDownDistanceText": "2nd & 6", "downDistanceText": "2nd & 6 at HOU 48"
        ]), league: .nfl))
        XCTAssertEqual(awayBall.possessionTeam?.abbreviation, "NYG")
        XCTAssertEqual(awayBall.liveSituation?.fieldProgress, 0.52)
        XCTAssertEqual(awayBall.liveSituation?.fieldPosition, "HOU 48")
        XCTAssertEqual(awayBall.liveSituation?.downDistance, "2nd & 6")
        XCTAssertEqual(awayBall.liveSituation?.period, 4)
        XCTAssertEqual(awayBall.liveSituation?.clock, "9:26")

        let ownSide = try XCTUnwrap(service.parseGame(Self.event(situation: [
            "possession": "19", "possessionText": "NYG 27", "yardLine": 73
        ]), league: .nfl))
        XCTAssertEqual(ownSide.liveSituation?.fieldProgress, 0.27)
        let homeBall = try XCTUnwrap(service.parseGame(Self.event(situation: [
            "possession": ["id": "34"], "possessionText": "NYG 27", "yardLine": 27
        ]), league: .nfl))
        XCTAssertEqual(homeBall.possessionTeam?.abbreviation, "HOU")
        XCTAssertEqual(homeBall.liveSituation?.fieldProgress, 0.73)
    }

    func testCollegeFootballSharesVerifiedPositionPolicyAndMidfieldHasNoInferredDirection() throws {
        let game = try XCTUnwrap(SportsService().parseGame(Self.event(situation: [
            "possession": ["team": ["id": "19"]], "possessionText": "HOU 34", "shortDownDistanceText": "1st & Goal"
        ]), league: .ncaaf))
        XCTAssertEqual(game.liveSituation?.fieldProgress, 0.66)
        XCTAssertEqual(game.liveSituation?.downDistance, "1st & Goal")
        let midfield = try XCTUnwrap(SportsService().parseGame(Self.event(situation: ["possession": "19", "possessionText": "50"]), league: .nfl))
        XCTAssertEqual(midfield.liveSituation?.fieldProgress, 0.5)
    }

    func testMissingAndUnknownPossessionNeverUseTheLastPlayOrAmbiguousYardLine() throws {
        for situation: [String: Any] in [
            ["lastPlay": ["team": ["id": "19"]], "possessionText": "NYG 27", "yardLine": 73],
            ["possession": "unknown", "possessionText": "NYG 27", "yardLine": 73],
            ["possession": ["id": "999"], "possessionText": "NYG 27"]
        ] {
            let game = try XCTUnwrap(SportsService().parseGame(Self.event(situation: situation), league: .nfl))
            XCTAssertNil(game.possessionTeam)
            XCTAssertNil(game.liveSituation?.fieldProgress)
        }
        for field in ["", "UNKNOWN 30", "NYG 70", "-4", "NYG -1"] {
            let game = try XCTUnwrap(SportsService().parseGame(Self.event(situation: [
                "possession": "19", "possessionText": field, "yardLine": 73
            ]), league: .nfl))
            XCTAssertNil(game.liveSituation?.fieldProgress)
            XCTAssertNil(game.liveSituation?.fieldPosition)
        }
    }

    func testPregameAndFinalDiscardStaleLiveFields() throws {
        for state in ["pre", "post"] {
            let game = try XCTUnwrap(SportsService().parseGame(Self.event(state: state, situation: [
                "possession": "19", "possessionText": "HOU 20", "shortDownDistanceText": "1st & 10"
            ]), league: .nfl))
            XCTAssertNil(game.liveSituation)
            XCTAssertNil(game.possessionTeam)
        }
    }

    func testBasketballSummaryOverridesCompetitionPossessionAndKeepsFieldFootballOnly() throws {
        let game = try XCTUnwrap(SportsService().parseGame(Self.event(situation: ["possession": "19"]), league: .nba,
            situationOverride: ["possession": ["id": "34"], "possessionText": "HOU 25", "shortDownDistanceText": "1st & 10"]))
        XCTAssertEqual(game.possessionTeam?.id, "34")
        XCTAssertNil(game.liveSituation?.fieldProgress)
        XCTAssertNil(game.liveSituation?.downDistance)
    }

    func testOnlyFootballAndBasketballExposeBallPossessionWhileOtherSportsKeepClock() throws {
        let event = Self.event(situation: ["possession": "19"])
        for league in [SportsLeague.nhl, .mlb] {
            let game = try XCTUnwrap(SportsService().parseGame(event, league: league))
            XCTAssertNil(game.possessionTeam, "\(league.title) must not render a basketball possession marker.")
            XCTAssertEqual(game.liveSituation?.period, 4)
            XCTAssertEqual(game.liveSituation?.clock, league == .mlb ? nil : "9:26")
        }
        for league in [SportsLeague.nfl, .ncaaf, .nba, .wnba] {
            let game = try XCTUnwrap(SportsService().parseGame(event, league: league))
            XCTAssertEqual(game.possessionTeam?.id, "19")
        }
    }

    func testLiveSnapshotCannotAttachAnotherMatchupOrReviveFinal() throws {
        let service = SportsService()
        let live = try XCTUnwrap(service.parseGame(Self.event(situation: ["possession": "19"]), league: .nfl))
        let final = try XCTUnwrap(service.parseGame(Self.event(state: "post", situation: ["possession": "19"]), league: .nfl))
        XCTAssertNil(SportsService.applyingLiveSnapshots([final], to: [live]).first?.possessionTeam)
        XCTAssertTrue(try XCTUnwrap(SportsService.applyingLiveSnapshots([final], to: [live]).first).isFinal)
        XCTAssertEqual(SportsService.applyingLiveSnapshots([live], to: [final]), [final])
        let wrong = SportsGame(eventID: live.eventID, league: live.league, date: live.date, state: "in", status: live.status,
            home: live.away, away: live.home, venue: "", broadcasts: "", link: "", liveSituation: live.liveSituation)
        XCTAssertEqual(SportsService.applyingLiveSnapshots([wrong], to: [live]), [live])
    }

    func testBackendCardsLoadBeforeSoftEnrichmentAndBasketballSummaryUsesCache() async throws {
        let fixture = try LiveSituationFixture(event: Self.event(), summarySituation: ["possession": ["id": "34"]])
        defer { fixture.session.invalidateAndCancel() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(SportsService.parseDate("2026-10-25T20:10:00Z"))
        let service = SportsService(backend: "https://live-fixture.example", session: fixture.session, calendar: calendar, now: { now })
        let schedule = try await service.schedule(leagues: [.nba], day: now)
        XCTAssertEqual(fixture.calls, 1, "Fetching the base schedule must not wait for live enrichment.")
        XCTAssertEqual(schedule.games.count, 1)
        XCTAssertNil(schedule.games.first?.possessionTeam)
        let enriched = await service.enrichLiveGames(schedule.games, day: now)
        XCTAssertEqual(enriched.first?.possessionTeam?.id, "34")
        XCTAssertEqual(fixture.calls, 3, "One league scoreboard plus one missing basketball summary enrich the visible card.")
        let cached = await service.enrichLiveGames(schedule.games, day: now)
        XCTAssertEqual(cached, enriched)
        XCTAssertEqual(fixture.calls, 3)
    }

    func testFailedEnrichmentKeepsTheVisibleBaseSchedule() async throws {
        let fixture = try LiveSituationFixture(event: Self.event(), failEnrichment: true)
        defer { fixture.session.invalidateAndCancel() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(SportsService.parseDate("2026-10-25T20:10:00Z"))
        let service = SportsService(backend: "https://live-fixture.example", session: fixture.session, calendar: calendar, now: { now })
        let schedule = try await service.schedule(leagues: [.nfl], day: now)
        let enriched = await service.enrichLiveGames(schedule.games, day: now)
        XCTAssertEqual(enriched, schedule.games)
        XCTAssertEqual(fixture.calls, 2)
    }

    func testBaseballPreservesOccupiedEmptyAndUnknownBasesWithBoundedCounts() throws {
        var event = Self.event(situation: ["onFirst": true, "onSecond": false,
            "onThird": ["athlete": ["id": "123"]], "balls": 2, "strikes": 1, "outs": 2])
        var competition = event.sportsObjects("competitions")[0]
        var status = competition.sportsObject("status")
        status["period"] = 7; status["periodPrefix"] = "Bottom"
        competition["status"] = status; event["competitions"] = [competition]
        let game = try XCTUnwrap(SportsService().parseGame(event, league: .mlb))
        let state = try XCTUnwrap(game.liveSituation?.baseball)
        XCTAssertEqual(state.firstOccupied, true)
        XCTAssertEqual(state.secondOccupied, false)
        XCTAssertEqual(state.thirdOccupied, true)
        XCTAssertEqual(state.balls, 2)
        XCTAssertEqual(state.strikes, 1)
        XCTAssertEqual(state.outs, 2)
        XCTAssertEqual(state.inning, 7)
        XCTAssertEqual(state.half, .bottom)
        XCTAssertNil(game.liveSituation?.clock)
        XCTAssertNil(game.possessionTeam)
        let missing = try XCTUnwrap(SportsService().parseGame(Self.event(situation: [
            "onFirst": NSNull(), "onSecond": [:], "onThird": 1, "balls": -1, "strikes": 5, "outs": true
        ]), league: .mlb)?.liveSituation?.baseball)
        XCTAssertNil(missing.firstOccupied)
        XCTAssertNil(missing.secondOccupied)
        XCTAssertNil(missing.thirdOccupied)
        XCTAssertNil(missing.balls)
        XCTAssertNil(missing.strikes)
        XCTAssertNil(missing.outs)
        XCTAssertFalse(missing.hasBaseData)
        for state in ["pre", "post"] {
            XCTAssertNil(SportsService().parseGame(Self.event(state: state, situation: ["onFirst": true, "outs": 1]), league: .mlb)?.liveSituation)
        }
    }

    func testSummaryCompetitorPossessionRequiresOneSupportedNonconflictingFlag() throws {
        var event = Self.event()
        var competition = event.sportsObjects("competitions")[0]
        var teams = competition.sportsObjects("competitors")
        teams[0]["possession"] = true; teams[1]["possession"] = false
        competition["competitors"] = teams
        competition["possessionArrowAvailable"] = true
        event["competitions"] = [competition]
        for league in [SportsLeague.nba, .wnba, .nfl, .ncaaf] {
            XCTAssertEqual(SportsService().parseGame(event, league: league)?.possessionTeam?.id, "34")
        }
        XCTAssertNil(SportsService().parseGame(event, league: .nba, situationOverride: ["possession": "19"])?.possessionTeam)
        competition["possessionArrowAvailable"] = false; event["competitions"] = [competition]
        XCTAssertNil(SportsService().parseGame(event, league: .nba)?.possessionTeam)
        competition["possessionArrowAvailable"] = true; teams[1]["possession"] = true
        competition["competitors"] = teams; event["competitions"] = [competition]
        XCTAssertNil(SportsService().parseGame(event, league: .nba)?.possessionTeam)
    }

    func testTeamColorsAreValidatedAndRetainedWhenSummaryOmitsThem() throws {
        XCTAssertEqual(SportsService.teamColor(" #0c2340 "), "0C2340")
        for invalid in ["", "red", "123", "abcdef00", "javascript:123456", "#GG1234"] { XCTAssertNil(SportsService.teamColor(invalid)) }
        var event = Self.event()
        var competition = event.sportsObjects("competitions")[0]
        var teams = competition.sportsObjects("competitors")
        var home = teams[0].sportsObject("team"), away = teams[1].sportsObject("team")
        home["color"] = "0c2340"; away["color"] = "BF0D3E"
        teams[0]["team"] = home; teams[1]["team"] = away
        competition["competitors"] = teams; event["competitions"] = [competition]
        let original = try XCTUnwrap(SportsService().parseGame(event, league: .nfl))
        XCTAssertEqual(original.home.primaryColorHex, "0C2340")
        let summary = try XCTUnwrap(SportsService().parseGame(Self.event(situation: ["possession": "19"]), league: .nfl))
        let updated = try XCTUnwrap(SportsService.applyingLiveSnapshots([summary], to: [original]).first)
        XCTAssertEqual(updated.home.primaryColorHex, "0C2340")
        XCTAssertEqual(updated.possessionTeam?.primaryColorHex, "BF0D3E")
    }

    func testGameCenterAlignsSparsePeriodsAndKeepsFeedStatOrderAndDisplayNames() async throws {
        var event = Self.event()
        var competition = event.sportsObjects("competitions")[0]
        var teams = competition.sportsObjects("competitors")
        teams[0]["linescores"] = [["period": 1, "value": 12], ["period": 3, "value": 18]]
        teams[1]["linescores"] = [["period": 1, "value": 10], ["period": 2, "displayValue": "14"]]
        competition["competitors"] = teams; event["competitions"] = [competition]
        let fixture = try LiveSituationFixture(event: event, summaryExtras: ["boxscore": ["teams": [
            ["team": ["id": "19"], "statistics": [["name": "rebounds", "displayName": "Total rebounds", "displayValue": "20"], ["name": "assists", "label": "Assists", "displayValue": "8"]]],
            ["team": ["id": "34"], "statistics": [["name": "rebounds", "displayValue": "18"], ["name": "assists", "displayValue": "9"]]]
        ]]])
        defer { fixture.session.invalidateAndCancel() }
        let service = SportsService(session: fixture.session)
        let game = try XCTUnwrap(service.parseGame(event, league: .nba))
        let center = try await service.center(game)
        XCTAssertEqual(center.scoring.map(\.period), [1, 2, 3])
        XCTAssertEqual(center.scoring.map(\.home), ["12", "—", "18"])
        XCTAssertEqual(center.scoring.map(\.away), ["10", "14", "—"])
        XCTAssertEqual(center.statistics.map(\.label), ["Total rebounds", "Assists"])
        XCTAssertEqual(center.statistics.map(\.away), ["20", "8"])
    }

    func testLiveBaseballCoreFallbackUsesExplicitAthleteAndCachesTheSnapshot() async throws {
        var event = Self.event()
        event["id"] = "401908044"
        var competition = event.sportsObjects("competitions")[0]
        var status = competition.sportsObject("status")
        status["period"] = 7; status["periodPrefix"] = "Top"
        competition["status"] = status; event["competitions"] = [competition]
        let fixture = try LiveSituationFixture(event: event, coreSituation: ["onThird": ["playerId": 1234], "outs": 1, "balls": 3, "strikes": 2])
        defer { fixture.session.invalidateAndCancel() }
        let service = SportsService(session: fixture.session)
        let game = try XCTUnwrap(service.parseGame(event, league: .mlb))
        let center = try await service.center(game)
        XCTAssertEqual(center.game.liveSituation?.baseball?.thirdOccupied, true)
        XCTAssertNil(center.game.liveSituation?.baseball?.firstOccupied)
        XCTAssertEqual(center.game.liveSituation?.baseball?.half, .top)
        XCTAssertEqual(fixture.calls, 2)
        _ = try await service.center(game)
        XCTAssertEqual(fixture.calls, 2)
    }

    private static func event(state: String = "in", situation: [String: Any] = [:]) -> [String: Any] {
        ["id": "event-42", "date": "2026-10-25T20:00:00Z", "competitions": [[
            "status": ["period": 4, "displayClock": "9:26", "type": ["state": state, "shortDetail": state == "post" ? "Final" : "9:26 - 4th"]],
            "situation": situation,
            "competitors": [
                ["homeAway": "home", "score": "20", "team": ["id": "34", "displayName": "Houston Texans", "abbreviation": "HOU"]],
                ["homeAway": "away", "score": "17", "team": ["id": "19", "displayName": "New York Giants", "abbreviation": "NYG"]]
            ]
        ]]]
    }
}

private final class LiveSituationFixture: @unchecked Sendable {
    let session: URLSession
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(event: [String: Any], summarySituation: [String: Any] = [:], failEnrichment: Bool = false,
         summaryExtras: [String: Any] = [:], coreSituation: [String: Any] = [:]) throws {
        let backend: [String: Any] = ["games": [["id": "event-42", "date": "2026-10-25T20:00:00Z", "state": "in", "status": "In Progress",
            "homeTeam": ["id": "34", "name": "Houston Texans", "abbreviation": "HOU", "score": "20"],
            "awayTeam": ["id": "19", "name": "New York Giants", "abbreviation": "NYG", "score": "17"]]], "failedDates": []]
        let backendData = try JSONSerialization.data(withJSONObject: backend)
        let scoreboardData = try JSONSerialization.data(withJSONObject: ["events": [event]])
        let summaryData = try JSONSerialization.data(withJSONObject: ["header": event, "situation": summarySituation].merging(summaryExtras) { _, extra in extra })
        let coreData = try JSONSerialization.data(withJSONObject: coreSituation)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveSituationProtocol.self]
        session = URLSession(configuration: configuration)
        LiveSituationProtocol.respond = { [weak self] request in
            guard let self, let url = request.url else { throw URLError(.cancelled) }
            self.lock.lock(); self.count += 1; self.lock.unlock()
            if url.host == "live-fixture.example" { return backendData }
            if failEnrichment { throw URLError(.cannotConnectToHost) }
            if url.path.hasSuffix("/scoreboard") { return scoreboardData }
            if url.path.hasSuffix("/summary") { return summaryData }
            if url.path.hasSuffix("/situation") { return coreData }
            throw URLError(.badURL)
        }
    }
}

private final class LiveSituationProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
