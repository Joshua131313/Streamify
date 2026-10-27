import XCTest
@testable import Streamify

final class SportsGameDataTests: XCTestCase {
    func testNHLTagKeepsSkatersPowerPlayEmptyNetAndTimerSeparate() throws {
        let date = try XCTUnwrap(SportsService.parseDate("2026-10-26T23:00:00Z"))
        var game = SportsGame(eventID: "42", league: .nhl, date: date, state: "in", status: "P2 8:42",
            home: .init(id: "1", name: "Boston", abbreviation: "BOS", logo: ""),
            away: .init(id: "2", name: "Toronto", abbreviation: "TOR", logo: ""), venue: "", broadcasts: "", link: "")
        var raw: [String: Any] = ["gameState": "LIVE", "startTimeUTC": "2026-10-26T23:00:00Z",
            "homeTeam": ["abbrev": "BOS"], "awayTeam": ["abbrev": "TOR"], "situationCode": "1541",
            "situation": ["awayTeam": ["strength": 5, "situationDescriptions": ["PP"]], "homeTeam": ["strength": 4], "timeRemaining": "0:42"]]
        game.liveSituation = .init(hockey: SportsService.hockeySituation(raw, game: game, observedAt: date))
        XCTAssertEqual(game.hockeySummary, "5 on 4 TOR PP 0:42")
        raw["situation"] = [:]; raw["situationCode"] = "0651"
        game.liveSituation = .init(hockey: SportsService.hockeySituation(raw, game: game, observedAt: date))
        XCTAssertEqual(game.hockeySummary, "6 on 5 TOR EN")
        XCTAssertNil(game.liveSituation?.hockey?.powerPlayTeamID, "An extra attacker must not invent a power play.")
        raw["awayTeam"] = ["abbrev": "OTHER"]
        XCTAssertNil(SportsService.hockeySituation(raw, game: game, observedAt: date))
    }

    func testLiveAlertTopicsAndTrackedGameLinksHaveOnlyKnownLeaguesAndTeamIdentity() throws {
        XCTAssertEqual(SportsAlertTopic.topic("NBA:2"), "streamify_live_nba_2")
        XCTAssertEqual(SportsAlertTopic.topic("WNBA:NY"), "streamify_live_wnba_ny")
        XCTAssertEqual(SportsAlertTopic.topic("NCAAF:130"), "streamify_live_college_football_130")
        for key in ["nba:2:3", "other:2", "nba:../../2", "nba:", "nba:🔴"] { XCTAssertNil(SportsAlertTopic.topic(key)) }
        let value = SportsTrackedGameAttributes(league: "nba", eventID: "401123456", away: "BOS", home: "TOR", awayID: "2", homeID: "3")
        let url = try XCTUnwrap(URLComponents(url: value.watchURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.path, "/watch")
        XCTAssertEqual(url.queryItems?.first { $0.name == "event" }?.value, "401123456")
        XCTAssertLessThan(try JSONEncoder().encode(value).count, 4096)
    }
    func testPlaysAreGroupedChronologicallyAndDriveCopiesAreDeduplicated() {
        func play(_ id: String, _ period: Int, _ sequence: Int) -> [String: Any] {
            ["id": id, "period": ["number": period], "sequenceNumber": sequence, "clock": ["displayValue": "2:18"], "text": "Play \(id)", "awayScore": 12, "homeScore": 15]
        }
        let first = play("a", 1, 1), second = play("b", 2, 2)
        let groups = SportsService.playByPlay(["plays": [second, first, ["text": "No period"]],
            "drives": ["previous": [["plays": [first]]], "current": ["plays": [play("c", 5, 3)]]]])
        XCTAssertEqual(groups.map(\.number), [1, 2, 5])
        XCTAssertEqual(groups.flatMap(\.plays).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(groups[0].plays[0].awayScore, "12")
        XCTAssertEqual(SportsLeague.nhl.periodTitle(4), "Overtime")
        XCTAssertEqual(SportsLeague.nba.periodTitle(6), "Overtime 2")
        XCTAssertEqual(SportsLeague.mlb.periodTitle(10), "Inning 10")
    }

    func testPlayerStatsKeepColumnAlignmentDNPAndTeamIdentity() throws {
        let home = SportsTeam(id: "1", name: "Home", abbreviation: "HOM", logo: "")
        let away = SportsTeam(id: "2", name: "Away", abbreviation: "AWY", logo: "")
        let game = SportsGame(eventID: "42", league: .nba, date: nil, state: "post", status: "Final", home: home, away: away, venue: "", broadcasts: "", link: "")
        let table: [String: Any] = ["labels": ["MIN", "PTS", "REB"], "athletes": [
            ["athlete": ["id": "p1", "displayName": "A Player"], "stats": ["32", "25"]],
            ["athlete": ["id": "p2", "displayName": "B Player"], "didNotPlay": true, "stats": []],
            ["athlete": ["id": "p1", "displayName": "Duplicate"], "stats": ["1", "2", "3"]]
        ]]
        let parsed = SportsService.playerStatistics(["boxscore": ["players": [
            ["team": ["id": "1"], "statistics": [table]], ["team": ["id": "other"], "statistics": [table]]
        ]]], game: game)
        let group = try XCTUnwrap(parsed.first)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(group.players.map(\.id), ["p1", "p2"])
        XCTAssertEqual(group.players[0].values, ["32", "25", "—"])
        XCTAssertEqual(group.players[1].values, ["—", "—", "—"])
        XCTAssertTrue(group.players[1].didNotPlay)
    }
}
