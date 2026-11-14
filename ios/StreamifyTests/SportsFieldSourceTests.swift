import XCTest
@testable import Streamify

final class SportsFieldSourceTests: XCTestCase {
    func testLookupUsesCanonicalEventAndUTCDate() throws {
        let event = game(.ncaaw, id: "401918849")
        let url = try XCTUnwrap(SportsFieldSource.lookupURL(for: event))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "streamify.watch")
        XCTAssertEqual(parts.path, "/api/field")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "league", value: "womens-college-basketball"),
            URLQueryItem(name: "gameId", value: "401918849"), URLQueryItem(name: "date", value: "20261114"),
            URLQueryItem(name: "inline", value: "1")])

        let tennis = SportsTennisMatch(tour: .wta, tournament: "WTA Finals", tournamentID: "382-2026", competitionID: "187384")
        let address = try XCTUnwrap(SportsFieldSource.lookupURL(for: game(.tennis, id: "espn-wta-187384", tennis: tennis)))
        XCTAssertTrue(address.absoluteString.contains("gameId=187384&tour=wta"))
        XCTAssertNil(SportsFieldSource.lookupURL(for: game(.tennis, id: "espn-wta-187385", tennis: tennis)))
        XCTAssertNil(SportsFieldSource.lookupURL(for: game(.nba, id: "abc/123")))
    }

    func testEmbedIsMatchSpecificAndLimitedToTheRequestedSport() throws {
        let url = "https://sportscore.com/embed/tracker/tennis/aryna-sabalenka-vs-elina-svitolina/?theme=dark"
        let data = Data(#"{"provider":"SportScore","embedUrl":"\#(url)"}"#.utf8)
        XCTAssertEqual(try SportsFieldSource.decode(data, league: .tennis), .embed(try XCTUnwrap(URL(string: url))))
        XCTAssertThrowsError(try SportsFieldSource.decode(data, league: .nba))
        XCTAssertNil(SportsFieldSource.embedURL("https://sportscore.com/embed/tracker/basketball/live/", league: .nba))
        XCTAssertNil(SportsFieldSource.embedURL(url.replacingOccurrences(of: "sportscore.com", with: "sportscore.com.invalid"), league: .tennis))
        XCTAssertNil(SportsFieldSource.embedURL(url.replacingOccurrences(of: "theme=dark", with: "redirect=evil"), league: .tennis))
        XCTAssertNil(SportsFieldSource.embedURL(url.replacingOccurrences(of: "sportscore.com", with: "user@sportscore.com"), league: .tennis))
    }

    func testExternalCoverageAndNullAvailability() throws {
        let url = "https://www.espn.com/nfl/game/_/gameId/401772510"
        let external = Data(#"{"provider":"ESPN","externalUrl":"\#(url)"}"#.utf8)
        XCTAssertEqual(try SportsFieldSource.decode(external, league: .nfl), .external(provider: "ESPN", url: try XCTUnwrap(URL(string: url))))
        let playByPlay = "https://www.espn.com/nba/playbyplay/_/gameId/401810034"
        XCTAssertEqual(try SportsFieldSource.decode(Data(#"{"provider":"ESPN","externalUrl":"\#(playByPlay)"}"#.utf8), league: .nba),
            .external(provider: "ESPN", url: try XCTUnwrap(URL(string: playByPlay))))
        let invalid = Data(#"{"provider":"ESPN","externalUrl":"https://www.espn.com.evil.example/nfl/game/_/gameId/401772510"}"#.utf8)
        XCTAssertThrowsError(try SportsFieldSource.decode(invalid, league: .nfl))
        XCTAssertNil(try SportsFieldSource.decode(Data("null".utf8), league: .nhl))
    }

    func testBuiltInTrackerRequiresExactOriginAndGameIdentity() throws {
        let lookup = try XCTUnwrap(SportsFieldSource.lookupURL(for: game(.nfl, id: "401772510")))
        let address = "https://streamify.watch/api/field-view?league=nfl&gameId=401772510"
        func decode(_ address: String) throws -> SportsFieldSource? {
            try SportsFieldSource.decode(Data(#"{"provider":"Streamify","embedUrl":"\#(address)"}"#.utf8), league: .nfl, requestURL: lookup)
        }
        let tracker = try XCTUnwrap(URL(string: address))
        XCTAssertEqual(try decode(address), .embed(tracker))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "401772510", with: "401772511")))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "league=nfl", with: "league=college-football")))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "streamify.watch", with: "streamify.watch.example")))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "streamify.watch", with: "streamify.watch:443")))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "/api/field-view", with: "/api/field%2dview")))
        XCTAssertThrowsError(try decode(address + "&gameId=401772510"))
        XCTAssertThrowsError(try decode(address + "#external"))

        let coverage = try XCTUnwrap(URL(string: "https://www.espn.com/nfl/game/_/gameId/401772510"))
        let otherGame = try XCTUnwrap(URL(string: "https://www.espn.com/nfl/game/_/gameId/401772511"))
        XCTAssertTrue(SportsFieldSource.permitsCoverageLink(coverage, from: tracker))
        XCTAssertFalse(SportsFieldSource.permitsCoverageLink(otherGame, from: tracker))
    }

    func testBuiltInTennisTrackerPreservesCanonicalTourAndDate() throws {
        let tennis = SportsTennisMatch(tour: .wta, tournament: "WTA Finals", tournamentID: "382-2026", competitionID: "187384")
        let lookup = try XCTUnwrap(SportsFieldSource.lookupURL(for: game(.tennis, id: "espn-wta-187384", tennis: tennis)))
        let address = "https://streamify.watch/api/field-view?league=tennis&gameId=187384&date=20261114&tour=wta"
        func decode(_ address: String) throws -> SportsFieldSource? {
            try SportsFieldSource.decode(Data(#"{"provider":"Streamify","embedUrl":"\#(address)"}"#.utf8), league: .tennis, requestURL: lookup)
        }
        XCTAssertEqual(try decode(address), .embed(try XCTUnwrap(URL(string: address))))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "tour=wta", with: "tour=atp")))
        XCTAssertThrowsError(try decode(address.replacingOccurrences(of: "date=20261114&", with: "")))
    }

    private func game(_ league: SportsLeague, id: String, tennis: SportsTennisMatch? = nil) -> SportsGame {
        SportsGame(eventID: id, league: league, date: SportsService.parseDate("2026-11-13T20:10:00-05:00"), state: "in", status: "Live",
            home: SportsTeam(id: "2", name: "Home", abbreviation: "HOM", logo: ""),
            away: SportsTeam(id: "1", name: "Away", abbreviation: "AWY", logo: ""), venue: "", broadcasts: "", link: "", tennis: tennis)
    }
}
