import XCTest
@testable import Streamify

final class SportsResultTests: XCTestCase {
    private func game(away: String, home: String, state: String = "post", status: String = "Final") -> SportsGame {
        SportsGame(eventID: "result-fixture", league: .nba, date: nil, state: state, status: status,
            home: SportsTeam(id: "home", name: "Home team", abbreviation: "HME", logo: "", score: home),
            away: SportsTeam(id: "away", name: "Away team", abbreviation: "AWY", logo: "", score: away),
            venue: "", broadcasts: "", link: "")
    }

    func testFinishedNumericScoresSelectCorrectHomeOrAwayWinner() {
        let homeWin = game(away: "99", home: "110")
        XCTAssertEqual(homeWin.winner?.id, "home")
        XCTAssertEqual(homeWin.resultLabel, "HME won")
        XCTAssertFalse(homeWin.isTied)
        let awayWin = game(away: "110.5", home: "100")
        XCTAssertEqual(awayWin.winner?.id, "away")
        XCTAssertEqual(awayWin.resultLabel, "AWY won")
        XCTAssertFalse(awayWin.isTied)
    }

    func testLiveAndUpcomingLeadsAreNotFinalResults() {
        for state in ["in", "pre"] {
            let leading = game(away: "122", home: "101", state: state, status: "4th quarter")
            XCTAssertNil(leading.winner)
            XCTAssertNil(leading.resultLabel)
            XCTAssertFalse(leading.isTied)
            XCTAssertFalse(game(away: "0", home: "0", state: state).isTied)
        }
    }

    func testFinishedTieIsSeparateFromWinningAndIncludesZeroScore() {
        for score in ["0", "102", "110.5"] {
            let tied = game(away: score, home: score)
            XCTAssertNil(tied.winner)
            XCTAssertTrue(tied.isTied)
            XCTAssertEqual(tied.resultLabel, "Tied game")
        }
    }

    func testMissingNonFiniteAndNegativeScoresNeverBecomeResults() {
        for invalid in ["", "TBD", "NaN", "inf", "Infinity", "-1"] {
            let invalidHome = game(away: "99", home: invalid)
            let invalidAway = game(away: invalid, home: "100")
            let invalidTie = game(away: invalid, home: invalid)
            for result in [invalidHome, invalidAway, invalidTie] {
                XCTAssertNil(result.winner, invalid)
                XCTAssertFalse(result.isTied, invalid)
                XCTAssertNil(result.resultLabel, invalid)
            }
        }
    }

    func testCancelledPostponedOrAbandonedEventsDoNotDeclareWinners() {
        for status in ["Canceled", "Cancelled", "Postponed", "Suspended", "No contest", "Abandoned"] {
            let event = game(away: "120", home: "100", status: status)
            XCTAssertNil(event.winner, status)
            XCTAssertFalse(event.isTied, status)
            XCTAssertNil(event.resultLabel, status)
            XCTAssertFalse(game(away: "0", home: "0", status: status).isTied, status)
        }
    }
}
