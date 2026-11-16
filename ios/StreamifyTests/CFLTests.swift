import Foundation
import XCTest
@testable import Streamify

final class CFLTests: XCTestCase {
    func testScheduleDetailsTeamsCalendarAndWatchUseCFLWorker() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CFLURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let now = try XCTUnwrap(SportsService.parseDate("2026-11-16T00:10:00Z"))
        let service = SportsService(backend: "https://legacy.invalid", session: session, calendar: calendar, now: { now })

        let schedule = try await service.schedule(leagues: [.cfl], day: now)
        let game = try XCTUnwrap(schedule.games.first)
        XCTAssertEqual(schedule.games.map(\.id), ["cfl:6676"])
        XCTAssertEqual(game.away.key(in: .cfl), "cfl:11")
        XCTAssertEqual(game.home.id, "7")
        XCTAssertTrue(game.isLive)
        XCTAssertEqual(game.away.score, "17")
        XCTAssertEqual(game.liveSituation?.period, 3)
        XCTAssertEqual(game.liveSituation?.clock, "12:45")
        XCTAssertEqual(game.possessionTeam?.id, "7")
        XCTAssertNil(game.liveSituation?.fieldProgress)
        XCTAssertNil(game.footballFieldPosition)
        XCTAssertEqual(game.broadcastLinks.map(\.label), ["TSN"])
        XCTAssertEqual(game.eventName, "113th Grey Cup")
        XCTAssertEqual(SportsWidgetPolicy.watchURL(for: game)?.absoluteString, "streamify://sports/watch?league=cfl&event=6676")

        let deepLinkGame = try await service.game(league: .cfl, eventID: "6676")
        XCTAssertEqual(deepLinkGame, game)
        let center = try await service.center(game)
        XCTAssertEqual(center.scoring.map(\.label), ["Quarter 1", "Quarter 2", "Quarter 3", "Quarter 4"])
        XCTAssertEqual(center.scoring.last?.away, "—")
        XCTAssertEqual(center.statistics.first?.home, "128")
        XCTAssertEqual(center.playByPlay.first?.plays.first?.clock, "05:12")

        let teams = try await service.teams(league: .cfl)
        XCTAssertEqual(teams.map(\.id), ["cfl:7", "cfl:11"])
        let team = try await service.profile(try XCTUnwrap(teams.first))
        XCTAssertEqual(team.venue, "McMahon Stadium")
        XCTAssertEqual(team.games.map(\.id), ["cfl:6676"])
        XCTAssertTrue(team.rosterUnavailable)
        let day = calendar.startOfDay(for: now)
        let markers = try await service.cflCalendar(first: day, last: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day)))
        XCTAssertEqual(markers.days, [day])
        XCTAssertFalse(markers.partial)

        let streams = try await service.streams(game)
        XCTAssertEqual(streams.map(\.title), ["Matchora · Grey Cup"])
        XCTAssertEqual(streams.first?.url.host, "matchora.pro")
    }

    func testCanonicalCFLIdentityAndFourQuartersStaySeparateFromAmericanFootball() throws {
        let game = try XCTUnwrap(SportsService.cflGame(CFLURLProtocol.game))
        XCTAssertEqual(SportsLeague.cfl.category, "canadian-football")
        XCTAssertEqual((1...5).map(SportsLeague.cfl.shortPeriodTitle), ["Q1", "Q2", "Q3", "Q4", "OT"])
        XCTAssertTrue(SportsSourceIdentity.leagueMatches("Canadian Football League", game: game))
        XCTAssertFalse(SportsSourceIdentity.leagueMatches("NFL", game: game, sport: "Football"))
        XCTAssertFalse(SportsSourceIdentity.leagueMatches("NCAA Football", game: game, sport: "Football"))
        var wrongLeague = CFLURLProtocol.game
        wrongLeague["league"] = "nfl"
        XCTAssertNil(SportsService.cflGame(wrongLeague))
        var invalid = CFLURLProtocol.game
        invalid["id"] = "6676/6674"
        XCTAssertNil(SportsService.cflGame(invalid))
    }
}

private final class CFLURLProtocol: URLProtocol {
    static var teams: [[String: Any]] {
        [["id": "7", "name": "Edmonton Elks", "abbrev": "EDM", "homeAway": "home", "score": "21", "linescores": ["7", "7", "7", "0"]],
         ["id": "11", "name": "Montreal Alouettes", "abbrev": "MTL", "homeAway": "away", "score": "17", "linescores": ["7", "10"]]]
    }

    static var game: [String: Any] {
        ["id": "6676", "league": "cfl", "date": "2026-11-15T23:00:00Z", "state": "in",
         "detail": "12:45 · Q3", "clock": "12:45", "period": 3, "periodCount": 4, "teams": teams,
         "venue": "McMahon Stadium", "broadcast": "TSN, CTV", "notes": ["113th Grey Cup"],
         "situation": ["possession": "7", "yardLine": 55, "possessionText": "55"],
         "broadcastLinks": [["label": "TSN", "url": "https://www.tsn.ca/live"],
                            ["label": "Invalid", "url": "https://www.tsn.ca.invalid/live"]],
         "details": ["teamStats": [["id": "7", "stats": [["name": "netYards", "label": "Net yards", "value": "128"]]]],
                     "scoringPlays": [["id": "31", "period": 1, "clock": "05:12", "text": "Edmonton touchdown", "homeScore": 7]]]]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "streamify.watch", url.scheme == "https",
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              query.first(where: { $0.name == "league" })?.value == "cfl" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let keys = Dictionary(uniqueKeysWithValues: query.compactMap { item in item.value.map { (item.name, $0) } })
        let payload: Any
        switch url.path {
        case "/api/scores" where keys["date"] == "20261115" && keys["live"] == "1": payload = [Self.game]
        case "/api/game" where keys["gameId"] == "6676": payload = [Self.game]
        case "/api/calendar" where keys["date"] == "20261115-20261116":
            payload = ["dates": ["2026-11-15T23:00:00Z", "2026-11-16T01:22:00Z", "invalid-date"], "partial": false]
        case "/api/teams" where keys["teamId"] == "7":
            var team = Self.teams[0]
            team["venue"] = "McMahon Stadium"; team["games"] = [Self.game]; team["rosterUnavailable"] = true
            payload = [team]
        case "/api/teams" where keys["teamId"] == nil: payload = Self.teams
        case "/api/streams" where keys["gameId"] == "6676":
            payload = [["label": "Matchora · Grey Cup", "embedUrl": "https://matchora.pro/embed/match/cfl6676"],
                       ["label": "Duplicate", "embedUrl": "https://matchora.pro/embed/match/cfl6676"],
                       ["label": "Invalid", "embedUrl": "http://example.invalid/player"]]
        default: client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
