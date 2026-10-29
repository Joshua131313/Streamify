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
    func testShortPlayerNamesRequireSurnameAndInitialAndRoutesRemainBounded() {
        XCTAssertTrue(TennisLiveFeed.samePlayer("Rottgering M.", "Mees Rottgering"))
        XCTAssertFalse(TennisLiveFeed.samePlayer("Rottgering M.", "Mark Bigun"))
        XCTAssertNil(TennisLiveFeed.historyURL("https://evil.example/atp/match/a-VS-b/test-2026/"))
        XCTAssertThrowsError(try TennisLiveFeed.parse("<html>Unavailable</html>"))
    }
}
