import Foundation
import XCTest
@testable import Streamify

/// Schedule/rank shapes captured from ESPN's public men's/women's scoreboards.
/// Summary and provider cases are intercepted synthetic fixtures; no live traffic.
final class CollegeBasketballTests: XCTestCase {
    func testBothLeaguesHaveDistinctEndpointsAndCompleteDivisionOneRequests() {
        for league in [SportsLeague.ncaam, .ncaaw] {
            XCTAssertEqual(league.sport, "basketball")
            XCTAssertEqual(league.category, "basketball")
            XCTAssertEqual(league.endpoint, "https://site.api.espn.com/apis/site/v2/sports/basketball/\(league.rawValue)")
            XCTAssertEqual(league.scoreboardParameters, ["&groups=50&limit=1000"])
            XCTAssertTrue(SportsLeague.allCases.contains(league))
        }
        XCTAssertEqual(SportsLeague.ncaam.title, "NCAAM")
        XCTAssertEqual(SportsLeague.ncaaw.title, "NCAAW")
        XCTAssertNotEqual(SportsLeague.ncaam.subtitle, SportsLeague.ncaaw.subtitle)
    }

    func testCapturedRankedGamesDecodeWithoutTreatingUnrankedSentinelAsARank() throws {
        for league in [SportsLeague.ncaam, .ncaaw] {
            let event = try CollegeBasketballFixture.event(league)
            let game = try XCTUnwrap(SportsService().parseGame(event, league: league))
            XCTAssertEqual(game.home.rank, 1)
            XCTAssertEqual(game.away.rank, league == .ncaam ? 14 : 20)
            XCTAssertTrue(game.home.rankedName.hasPrefix("#1 "))
            let widget = try XCTUnwrap(SportsWidgetPolicy.parseScoreboard(JSONSerialization.data(withJSONObject: ["events": [event]]), league: league).first)
            XCTAssertEqual(widget.home.rank, game.home.rank)
            XCTAssertEqual(widget.away.rank, game.away.rank)
            let format = event.sportsObjects("competitions")[0].sportsObject("format").sportsObject("regulation")
            XCTAssertEqual(format["periods"] as? Int, league.regulationPeriods)
            var unranked = event
            var competition = event.sportsObjects("competitions")[0]
            var opponents = competition.sportsObjects("competitors")
            for index in opponents.indices { opponents[index]["curatedRank"] = ["current": index == 0 ? 99 : 0] }
            competition["competitors"] = opponents; unranked["competitions"] = [competition]
            let noRank = try XCTUnwrap(SportsService().parseGame(unranked, league: league))
            XCTAssertNil(noRank.home.rank); XCTAssertNil(noRank.away.rank)
            XCTAssertFalse(noRank.home.rankedName.hasPrefix("#"))
            let noWidgetRank = try XCTUnwrap(SportsWidgetPolicy.parseScoreboard(JSONSerialization.data(withJSONObject: ["events": [unranked]]), league: league).first)
            XCTAssertNil(noWidgetRank.home.rank); XCTAssertNil(noWidgetRank.away.rank)
        }
    }

    func testScheduleUsesBothCollegeFeedsAndMergesAdjacentUTCResponses() async throws {
        let session = CollegeBasketballFixture.session()
        defer { session.invalidateAndCancel() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        let service = SportsService(backend: "https://unsupported-college-backend.test", session: session,
            calendar: calendar, now: { day.addingTimeInterval(12 * 3600) })
        let schedule = try await service.schedule(leagues: [.ncaam, .ncaaw], day: day)
        XCTAssertFalse(schedule.partial)
        XCTAssertEqual(Set(schedule.games.map(\.league)), [.ncaam, .ncaaw])
        XCTAssertEqual(Set(schedule.games.map(\.eventID)), ["401906769", "401918849"])
        XCTAssertEqual(schedule.games.count, 2)
        XCTAssertTrue(schedule.games.allSatisfy { calendar.isDate($0.date!, inSameDayAs: day) })
    }

    func testMenUseTwoHalvesWomenUseFourQuartersAndBothHandleOvertime() {
        XCTAssertEqual([1, 2, 3, 4].map(SportsLeague.ncaam.shortPeriodTitle), ["H1", "H2", "OT", "OT2"])
        XCTAssertEqual([1, 2, 3, 4, 5, 6].map(SportsLeague.ncaaw.shortPeriodTitle), ["Q1", "Q2", "Q3", "Q4", "OT", "OT2"])
        XCTAssertEqual(SportsLeague.ncaam.periodTitle(2), "Half 2")
        XCTAssertEqual(SportsLeague.ncaam.periodTitle(3), "Overtime")
        XCTAssertEqual(SportsLeague.ncaaw.periodTitle(4), "Quarter 4")
        XCTAssertEqual(SportsLeague.ncaaw.periodTitle(5), "Overtime")
    }

    func testGameCenterUsesCollegeSummaryScoringPlayersStatsAndPlayPeriods() async throws {
        let session = CollegeBasketballFixture.session()
        defer { session.invalidateAndCancel() }
        let service = SportsService(session: session)
        for league in [SportsLeague.ncaam, .ncaaw] {
            let game = try XCTUnwrap(service.parseGame(try CollegeBasketballFixture.event(league), league: league))
            let center = try await service.center(game)
            XCTAssertEqual(center.game.league, league)
            XCTAssertEqual(center.scoring.count, league.regulationPeriods)
            XCTAssertEqual(center.scoring.last?.label, league == .ncaam ? "Half 2" : "Quarter 4")
            XCTAssertEqual(center.statistics.first { $0.id == "threePointFieldGoalsMade-threePointFieldGoalsAttempted" }?.home, "8-20")
            XCTAssertEqual(center.playerStats.first?.labels, ["MIN", "PTS", "REB", "AST"])
            XCTAssertEqual(center.playerStats.first?.players.first?.values, ["20", "12", "4", "3"])
            XCTAssertEqual(center.playByPlay.map(\.number), [1, league.regulationPeriods])
            XCTAssertEqual(center.game.possessionTeam?.id, game.home.id)
        }
    }

    func testProviderLeagueLabelsNeverConfuseMenWomenNBAOrUnqualifiedNCAA() {
        let men = CollegeBasketballFixture.game(.ncaam), women = CollegeBasketballFixture.game(.ncaaw)
        for label in ["NCAAM", "NCAAB", "Men's College Basketball", "NCAA Men's Basketball"] {
            XCTAssertTrue(SportsSourceIdentity.leagueMatches(label, game: men))
            XCTAssertFalse(SportsSourceIdentity.leagueMatches(label, game: women))
        }
        for label in ["NCAAW", "WNCAAB", "Women's College Basketball", "NCAA Women's Basketball"] {
            XCTAssertTrue(SportsSourceIdentity.leagueMatches(label, game: women))
            XCTAssertFalse(SportsSourceIdentity.leagueMatches(label, game: men))
        }
        for label in ["NBA", "WNBA", "NCAAF", "NCAA", "NCAA Division 1", "Basketball"] {
            XCTAssertFalse(SportsSourceIdentity.leagueMatches(label, game: men, sport: "Basketball"))
            XCTAssertFalse(SportsSourceIdentity.leagueMatches(label, game: women, sport: "Basketball"))
        }
        XCTAssertTrue(SportsSourceIdentity.teamsMatch("#4 University of UConn vs No. 20 Duke", game: men))
        XCTAssertFalse(SportsSourceIdentity.teamsMatch("UConn vs Duke State", game: men))
        XCTAssertFalse(SportsSourceIdentity.teamsMatch("Huskies vs Blue Devils", game: men))
    }

    func testMatchoraStreamFreeAndDaddyLiveUsePublishedGenderSpecificListings() {
        for league in [SportsLeague.ncaam, .ncaaw] {
            let game = CollegeBasketballFixture.game(league), start = game.date!
            var event: [String: Any] = ["id": "2601717", "home": "UConn", "away": "Duke", "league": league.title,
                "sport": "Basketball", "kickoff": start.timeIntervalSince1970, "finished": false]
            XCTAssertTrue(MatchoraProvider.matches(event, game: game, now: start))
            event["league"] = league == .ncaam ? "NCAAW" : "NCAAM"
            XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: start))
            event["league"] = "NCAA Division 1"
            XCTAssertFalse(MatchoraProvider.matches(event, game: game, now: start))
            var stream: [String: Any] = ["stream_key": "published-college-event", "category": "basketball", "league": league.title,
                "name": "UConn vs Duke", "match_timestamp": start.timeIntervalSince1970]
            XCTAssertTrue(StreamFreeProvider.matches(stream, game: game, now: start))
            stream["league"] = "NBA"
            XCTAssertFalse(StreamFreeProvider.matches(stream, game: game, now: start))
            let html = CollegeBasketballFixture.daddyHTML(label: league.title)
            XCTAssertEqual(DaddyLiveProvider.channels(in: html, game: game, now: start).first?.watchURL.absoluteString, "https://thedaddy.pk/watch.php?id=12")
            XCTAssertTrue(DaddyLiveProvider.channels(in: CollegeBasketballFixture.daddyHTML(label: league == .ncaam ? "NCAAW" : "NCAAM"), game: game, now: start).isEmpty)
        }
    }

    func testTimStreamsUsesExactESPNIdentityAndLegacyListsRequireExplicitCollegeLeague() {
        for league in [SportsLeague.ncaam, .ncaaw] {
            let game = CollegeBasketballFixture.game(league)
            var item: [String: Any] = ["url": "published-college-event-\(game.eventID)", "genre": 7, "isevent": true, "vip": false]
            XCTAssertTrue(SportsService.timstEventMatches(item, game: game))
            item["url"] = "published-college-event-\(league == .ncaam ? "401900002" : "401900001")"
            XCTAssertFalse(SportsService.timstEventMatches(item, game: game))
            item["url"] = "published-college-event-\(game.eventID)"; item["genre"] = 8
            XCTAssertFalse(SportsService.timstEventMatches(item, game: game))
            var legacy: [String: Any] = ["id": "published", "category": "basketball", "league": league.title,
                "date": game.date!.timeIntervalSince1970 * 1000,
                "teams": ["home": ["name": "UConn"], "away": ["name": "Duke"]], "sources": [["source": "alpha", "id": "published"]]]
            XCTAssertNotNil(SportsService.matchingStreamMatch([legacy], game: game, now: game.date!))
            legacy["league"] = league == .ncaam ? "NCAAW" : "NCAAM"
            XCTAssertNil(SportsService.matchingStreamMatch([legacy], game: game, now: game.date!))
            legacy.removeValue(forKey: "league")
            XCTAssertNil(SportsService.matchingStreamMatch([legacy], game: game, now: game.date!))
        }
    }

    func testChatFavoritesTrackingAndWidgetLinksKeepCollegeNamespacesSeparate() throws {
        let men = CollegeBasketballFixture.game(.ncaam), women = CollegeBasketballFixture.game(.ncaaw)
        XCTAssertNotEqual(men.id, women.id)
        XCTAssertEqual(men.home.key(in: .ncaam), "mens-college-basketball:41")
        XCTAssertEqual(women.home.key(in: .ncaaw), "womens-college-basketball:41")
        XCTAssertEqual(SportsChatContract.room(league: .ncaam, away: "UCONN", home: "DUKE", eventID: "401920912"), "NCAAM-401920912")
        XCTAssertEqual(SportsChatContract.room(league: .ncaaw, away: "UCONN", home: "DUKE", eventID: "401920912"), "NCAAW-401920912")
        XCTAssertNil(SportsChatContract.room(league: .ncaam, away: "UCONN", home: "DUKE"))
        XCTAssertNil(SportsChatContract.room(league: .ncaaw, away: "UCONN", home: "DUKE", eventID: "../1"))
        for game in [men, women] {
            let url = try XCTUnwrap(SportsWidgetPolicy.watchURL(for: game))
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.queryItems?.first { $0.name == "league" }?.value, game.league.rawValue)
        }
    }
}

private enum CollegeBasketballFixture {
    static func envelope(_ league: SportsLeague) throws -> [String: Any] {
        let name = league == .ncaam ? "college-basketball-men-scoreboard" : "college-basketball-women-scoreboard"
        let url = try XCTUnwrap(Bundle(for: CollegeBasketballTests.self).url(forResource: name, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    static func event(_ league: SportsLeague) throws -> [String: Any] { try XCTUnwrap(envelope(league).sportsObjects("events").first) }
    static func game(_ league: SportsLeague) -> SportsGame {
        SportsGame(eventID: league == .ncaam ? "401900001" : "401900002", league: league,
            date: ISO8601DateFormatter().date(from: "2026-11-02T23:00:00Z"), state: "in", status: "Live",
            home: SportsTeam(id: "41", name: "UConn Huskies", abbreviation: "UCONN", logo: "", streamNames: ["UConn"]),
            away: SportsTeam(id: "150", name: "Duke Blue Devils", abbreviation: "DUKE", logo: "", streamNames: ["Duke"]),
            venue: "", broadcasts: "", link: "")
    }
    static func daddyHTML(label: String) -> String {
        """
        <div class="schedule__day"><h2 class="schedule__dayTitle">Monday 2 Nov 2026</h2>
        <div class="schedule__event"><span class="schedule__time" data-time="23:00">23:00</span>
        <span class="schedule__eventTitle">\(label): UConn vs Duke</span>
        <div class="schedule__channels"><a href="/watch.php?id=12">Published feed</a></div></div></div>
        """
    }
    static func summary(_ league: SportsLeague) throws -> [String: Any] {
        var header = try event(league)
        var competition = header.sportsObjects("competitions")[0]
        let count = league.regulationPeriods
        var opponents = competition.sportsObjects("competitors")
        for index in opponents.indices {
            opponents[index]["score"] = index == 0 ? "75" : "65"
            opponents[index]["linescores"] = (1...count).map { ["period": $0, "displayValue": "\(15 + $0)"] as [String: Any] }
        }
        let homeID = opponents.first { $0.sportsText("homeAway") == "home" }!.sportsObject("team").sportsText("id")
        competition["competitors"] = opponents
        competition["status"] = ["period": 1, "displayClock": "15:23", "type": ["state": "in", "shortDetail": "Live"]]
        header["competitions"] = [competition]
        let stats: [[String: Any]] = [["name": "threePointFieldGoalsMade-threePointFieldGoalsAttempted", "label": "3-pointers", "displayValue": "8-20"]]
        let player: [String: Any] = ["athlete": ["id": "900", "displayName": "Fixture player"], "stats": ["20", "12", "4", "3"]]
        let playerTable: [String: Any] = ["name": "basketball", "labels": ["MIN", "PTS", "REB", "AST"], "athletes": [player]]
        let boxscore: [String: Any] = ["teams": [["team": ["id": homeID], "statistics": stats]],
            "players": [["team": ["id": homeID], "statistics": [playerTable]]]]
        let plays: [[String: Any]] = [1, count].map {
            ["id": "play-\($0)", "period": ["number": $0], "clock": ["displayValue": "1:23"], "text": "Fixture made shot", "sequenceNumber": $0]
        }
        return ["header": header, "situation": ["possessionTeamID": homeID], "boxscore": boxscore, "plays": plays]
    }
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollegeBasketballProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class CollegeBasketballProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let league: SportsLeague = url.path.contains("/womens-college-basketball/") ? .ncaaw : .ncaam
            guard url.host == "site.api.espn.com", url.path.hasPrefix("/apis/site/v2/sports/basketball/\(league.rawValue)/") else { throw URLError(.badURL) }
            let body: [String: Any]
            if url.path.hasSuffix("/scoreboard") {
                let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
                guard parts?.queryItems?.first(where: { $0.name == "groups" })?.value == "50",
                      parts?.queryItems?.first(where: { $0.name == "limit" })?.value == "1000" else { throw URLError(.badURL) }
                body = try CollegeBasketballFixture.envelope(league)
            } else if url.path.hasSuffix("/summary") { body = try CollegeBasketballFixture.summary(league) }
            else { throw URLError(.badURL) }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
