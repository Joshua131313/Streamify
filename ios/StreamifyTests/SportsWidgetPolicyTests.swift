import XCTest
@testable import Streamify

final class SportsWidgetPolicyTests: XCTestCase {
    private var toronto: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-24T04:30:00Z")!

    func testScoreboardParserUsesRealTeamIdentityScoresAndCompetitionStatus() throws {
        let raw = scoreboardEvent(id: 401810123, date: "2026-10-24T02:00:00Z", state: "in")
        let data = try JSONSerialization.data(withJSONObject: ["events": [raw]])
        let games = try SportsWidgetPolicy.parseScoreboard(data, league: .nba)
        let game = try XCTUnwrap(games.first)
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(game.id, "nba:401810123")
        XCTAssertEqual(game.away.id, "100")
        XCTAssertEqual(game.away.abbreviation, "BOS")
        XCTAssertEqual(game.away.score, "98")
        XCTAssertEqual(game.home.score, "105")
        XCTAssertEqual(game.status, "4th · 02:18")
        XCTAssertEqual(game.home.logoURL?.host, "a.espncdn.com")
        XCTAssertTrue(game.isLive)
    }

    func testParserSkipsInvalidEventAndMissingTeamWithoutInventingGames() throws {
        let valid = scoreboardEvent(id: "401810123", date: "2026-10-24T02:00:00Z", state: "in")
        let invalid = scoreboardEvent(id: "../../wrong", date: "2026-10-24T02:00:00Z", state: "in")
        let missing = ["id": "401810125", "competitions": [["competitors": []]]] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: ["events": [valid, invalid, missing]])
        XCTAssertEqual(try SportsWidgetPolicy.parseScoreboard(data, league: .ncaaf).map(\.eventID), ["401810123"])
        XCTAssertTrue(try SportsWidgetPolicy.parseScoreboard(Data("{\"events\":[]}".utf8), league: .nba).isEmpty)
        XCTAssertThrowsError(try SportsWidgetPolicy.parseScoreboard(Data("<html>Busy</html>".utf8), league: .nba))
    }

    func testTodayIncludesOvernightLiveAndCanonicalFinalRemovesStaleLiveCopy() throws {
        let events = [
            scoreboardEvent(id: "401810100", date: "2026-10-24T03:30:00Z", state: "in"),
            scoreboardEvent(id: "401810101", date: "2026-10-24T03:00:00Z", state: "in"),
            scoreboardEvent(id: "401810101", date: "2026-10-24T03:00:00Z", state: "post"),
            scoreboardEvent(id: "401810102", date: "2026-10-23T03:00:00Z", state: "in"),
            scoreboardEvent(id: "401810103", date: "2026-10-25T18:00:00Z", state: "in"),
            scoreboardEvent(id: "401810104", date: "2026-10-24T18:00:00Z", state: "pre")
        ]
        let data = try JSONSerialization.data(withJSONObject: ["events": events])
        let games = try SportsWidgetPolicy.parseScoreboard(data, league: .nba)
        XCTAssertEqual(SportsWidgetPolicy.liveGames(games, now: now, calendar: toronto).map(\.eventID), ["401810100"],
            "Only the actual current/previous-local-day live game belongs in the widget; final wins deduplication")
    }

    func testFeedDatesCoverPreviousAndCurrentLocalDaysAcrossUTCBoundaries() {
        XCTAssertEqual(SportsWidgetPolicy.scoreboardDates(now: now, calendar: toronto), ["20261023", "20261024", "20261025"])
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(SportsWidgetPolicy.scoreboardDates(now: now, calendar: tokyo), ["20261022", "20261023", "20261024"])
    }

    func testWatchDeepLinkContainsOnlyTheKnownLeagueAndStrictNumericEvent() throws {
        let data = try JSONSerialization.data(withJSONObject: ["events": [scoreboardEvent(id: "401810123", date: "2026-10-24T03:30:00Z", state: "in")]])
        let game = try XCTUnwrap(try SportsWidgetPolicy.parseScoreboard(data, league: .ncaaf).first)
        let url = try XCTUnwrap(SportsWidgetPolicy.watchURL(for: game))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "streamify")
        XCTAssertEqual(components.host, "sports")
        XCTAssertEqual(components.path, "/watch")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "league", value: "college-football"), URLQueryItem(name: "event", value: "401810123")])
        XCTAssertEqual(SportsWidgetPolicy.sportsURL.absoluteString, "streamify://sports")
        for invalid in ["", "-1", "1&event=2", "１２３", "../123", String(repeating: "1", count: 33)] {
            XCTAssertFalse(SportsWidgetPolicy.validEventID(invalid))
        }
    }

    private func scoreboardEvent(id: Any, date: String, state: String) -> [String: Any] {
        ["id": id, "date": date, "competitions": [[
            "status": ["type": ["state": state, "shortDetail": state == "post" ? "Final" : "4th · 02:18"]],
            "competitors": [
                ["homeAway": "away", "score": 98, "team": ["id": 100, "displayName": "Boston Harbor", "abbreviation": "BOS", "logo": "https://a.espncdn.com/boston.png"]],
                ["homeAway": "home", "score": ["displayValue": "105"], "team": ["id": "200", "displayName": "Toronto Towers", "abbreviation": "TOR", "logos": [["href": "https://a.espncdn.com/toronto.png"]]]]
            ]
        ]]]
    }
}
