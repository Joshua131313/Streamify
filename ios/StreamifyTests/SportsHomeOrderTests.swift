import XCTest
@testable import Streamify

final class SportsHomeOrderTests: XCTestCase {
    func testPopulatedLeaguesComeFirstWithStableOrderAndNoRemovedLeagues() {
        XCTAssertEqual(SportsHomeOrder.leagues(withGames: [.nba, .mlb]), [.nba, .mlb, .nfl, .wnba, .nhl])
        XCTAssertEqual(SportsHomeOrder.leagues(withGames: []), SportsLeague.allCases)
        XCTAssertEqual(SportsHomeOrder.leagues(withGames: Set(SportsLeague.allCases)), SportsLeague.allCases)
    }
}
