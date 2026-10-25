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
    init(event: [String: Any], summarySituation: [String: Any] = [:], failEnrichment: Bool = false) throws {
        let backend: [String: Any] = ["games": [["id": "event-42", "date": "2026-10-25T20:00:00Z", "state": "in", "status": "In Progress",
            "homeTeam": ["id": "34", "name": "Houston Texans", "abbreviation": "HOU", "score": "20"],
            "awayTeam": ["id": "19", "name": "New York Giants", "abbreviation": "NYG", "score": "17"]]], "failedDates": []]
        let backendData = try JSONSerialization.data(withJSONObject: backend)
        let scoreboardData = try JSONSerialization.data(withJSONObject: ["events": [event]])
        let summaryData = try JSONSerialization.data(withJSONObject: ["header": event, "situation": summarySituation])
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
