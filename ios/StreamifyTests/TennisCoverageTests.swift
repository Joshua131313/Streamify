import XCTest
@testable import Streamify

final class TennisCoverageTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "html") ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func games() throws -> [SportsGame] { try TennisLiveFeed.parse(fixture("tennislive-schedule")) }
    private func live() throws -> SportsGame { try XCTUnwrap(games().first { $0.away.name == "Mees Rottgering" && $0.tennis?.isDoubles == false }) }

    func testCapturedSiouxFallsIsLiveWithConfirmedServerAndScore() throws {
        let game = try live()
        XCTAssertTrue(game.isLive)
        XCTAssertEqual(game.tennis?.tour, .challenger)
        XCTAssertEqual(game.tennis?.servingID, game.away.id)
        XCTAssertEqual(game.tennis?.awaySets, ["4"])
        XCTAssertTrue(game.tennis?.historyURL?.contains("sioux-falls") == true)
    }
    func testChallenger125AndWTA125AreIncludedAlongsideSeparateDoubles() throws {
        let games = try games()
        XCTAssertTrue(games.contains { $0.tennis?.tournament.contains("Brest") == true && $0.tennis?.tour == .challenger })
        XCTAssertTrue(games.contains { $0.tennis?.tournament.contains("Queretaro") == true && $0.tennis?.tour == .wta })
        XCTAssertTrue(games.contains { $0.tennis?.isDoubles == true })
    }
    func testScheduledChallengerIdentityBecomesLiveWithoutDuplicatingTheCard() throws {
        let old = try XCTUnwrap(SportsTennisExplorer.parse(fixture("tennislive-challenger-scheduled")).first)
        XCTAssertEqual(old.state, "pre")
        let merged = TennisLiveFeed.merge([old], live: [try live()])
        XCTAssertEqual(merged.count, 1)
        let game = try XCTUnwrap(merged.first)
        XCTAssertEqual(game.id, old.id)
        XCTAssertTrue(game.isLive)
        XCTAssertEqual(game.tennis?.servingID, old.away.id)
    }
    func testHistoryHasEightGamesAndOnlyTheActualBreak() throws {
        let history = try TennisLiveFeed.history(fixture("tennislive-points"), game: live())
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.games.count, 8)
        XCTAssertEqual(history.first?.games.filter(\.isBreak).map(\.number), [5])
        XCTAssertEqual(history.first?.games.first?.points.first, "0–15")
        XCTAssertEqual(history.first?.games.first?.winner, "Kaylan Bigun")
    }
    func testHistoryCannotBeShownForAnotherPlayerOrDate() throws {
        let game = try live()
        let wrong = SportsGame(eventID: game.eventID, league: .tennis, date: game.date?.addingTimeInterval(-10 * 86400), state: game.state,
            status: game.status, home: game.home, away: game.away, venue: "", broadcasts: "", link: game.link, tennis: game.tennis)
        XCTAssertThrowsError(try TennisLiveFeed.history(fixture("tennislive-points"), game: wrong))
    }
    func testOfficialNameAndCityHeaderMergeThroughPublishedTournamentRoute() throws {
        let game = try live()
        let oldMetadata = SportsTennisMatch(tour: .atp, tournament: "Erste Bank Open", tournamentID: "old")
        let freshMetadata = SportsTennisMatch(tour: .atp, tournament: "Vienna", tournamentID: "new", source: "tennislive",
            historyURL: "https://www.tennislive.net/atp/match/mees-rottgering-VS-kaylan-bigun/erste-bank-open-vienna-2026/")
        func copy(_ id: String, _ metadata: SportsTennisMatch) -> SportsGame {
            SportsGame(eventID: id, league: .tennis, date: game.date, state: game.state, status: game.status,
                home: game.home, away: game.away, venue: "", broadcasts: "", link: "", tennis: metadata)
        }
        XCTAssertEqual(TennisLiveFeed.merge([copy("espn-atp-1", oldMetadata)], live: [copy("fresh", freshMetadata)]).map(\.eventID), ["espn-atp-1"])
    }
    func testPointWinnerHandlesDeuceAndDoesNotAssignMissingPoints() {
        XCTAssertEqual(TennisLiveFeed.pointWinner(previous: "0–0", current: "15–0"), 0)
        XCTAssertEqual(TennisLiveFeed.pointWinner(previous: "A–40", current: "40–40"), 1)
        XCTAssertNil(TennisLiveFeed.pointWinner(previous: "0–0", current: "30–0"))
    }
    func testOptionalMiddleNameMergesReversedTokyoFeedsAndRetainsESPNIdentity() throws {
        let date = SportsService.parseDate("2026-10-29T03:05:00Z")!
        let leylah = SportsTeam(id: "wta-3641", name: "Leylah Fernandez", abbreviation: "L. Fernandez", logo: "https://example.com/ca.png", portrait: "https://example.com/leylah.jpg")
        let elise = SportsTeam(id: "wta-2221", name: "Elise Mertens", abbreviation: "E. Mertens", logo: "https://example.com/be.png", record: "Seed 5")
        let original = SportsGame(eventID: "espn-wta-185678", league: .tennis, date: date, state: "in", status: "1st Set", home: leylah, away: elise,
            venue: "", broadcasts: "", link: "", tennis: SportsTennisMatch(tour: .wta, tournament: "Toray Pan Pacific Open Tennis", tournamentID: "1056-2026", competitionID: "185678"))
        let freshLeylah = SportsTeam(id: "tl-wta-1", name: "Leylah Annie Fernandez", abbreviation: "Leylah Annie Fernandez", logo: "", score: "0")
        let freshElise = SportsTeam(id: "tl-wta-2", name: "Elise Mertens", abbreviation: "Elise Mertens", logo: "", score: "0")
        let live = SportsGame(eventID: "tennislive-wta-1-1-2", league: .tennis, date: date.addingTimeInterval(300), state: "in", status: "1. set", home: freshElise, away: freshLeylah,
            venue: "", broadcasts: "", link: "", tennis: SportsTennisMatch(tour: .wta, tournament: "Toray Pan Pacific Open - Tokyo", tournamentID: "tl-wta-1",
                awaySets: ["3"], homeSets: ["2"], awayPoint: "30", homePoint: "40", servingID: freshElise.id, source: "tennislive",
                historyURL: "https://www.tennislive.net/wta/match/leylah-annie-fernandez-VS-elise-mertens/toray-pan-pacific-open-tokyo-2026/"))
        let merged = TennisLiveFeed.merge([original], live: [live])
        XCTAssertEqual(merged.count, 1)
        let result = try XCTUnwrap(merged.first)
        XCTAssertEqual(result.eventID, original.eventID)
        XCTAssertEqual(result.tennis?.competitionID, "185678")
        XCTAssertEqual(result.tennis?.source, "espn")
        XCTAssertEqual(result.tennis?.awaySets, ["2"])
        XCTAssertEqual(result.tennis?.homeSets, ["3"])
        XCTAssertEqual(result.tennis?.awayPoint, "40")
        XCTAssertEqual(result.tennis?.homePoint, "30")
        XCTAssertEqual(result.tennis?.servingID, elise.id)
        XCTAssertEqual(result.home.portrait, leylah.portrait)
        XCTAssertEqual(result.away.logo, elise.logo)
    }
    func testMiddleNameMatchingDoesNotCombineDifferentPeopleOrDoublesPartners() {
        XCTAssertTrue(TennisLiveFeed.samePlayer("Leylah Annie Fernandez", "Leylah Fernandez"))
        XCTAssertTrue(TennisLiveFeed.samePlayer("Leylah Fernandez", "Leylah Annie Fernandez"))
        XCTAssertFalse(TennisLiveFeed.samePlayer("Leylah Annie Fernandez", "Leanne Fernandez"))
        XCTAssertFalse(TennisLiveFeed.samePlayer("Leylah Annie Fernandez", "Leylah Marie Fernandez"))
        XCTAssertFalse(TennisLiveFeed.samePlayer("L. Fernandez", "Leylah Annie Fernandez"))
        XCTAssertFalse(TennisLiveFeed.samePlayer("Joe Salisbury / Neal Skupski", "Joe / Skupski"))
    }
    func testShortPlayerNamesRequireSurnameAndInitialAndRoutesRemainBounded() {
        XCTAssertTrue(TennisLiveFeed.samePlayer("Rottgering M.", "Mees Rottgering"))
        XCTAssertFalse(TennisLiveFeed.samePlayer("Rottgering M.", "Mark Bigun"))
        XCTAssertNil(TennisLiveFeed.historyURL("https://evil.example/atp/match/a-VS-b/test-2026/"))
        XCTAssertThrowsError(try TennisLiveFeed.parse("<html>Unavailable</html>"))
    }
}
