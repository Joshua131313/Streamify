import XCTest
@testable import Streamify

final class SportsScheduledPhaseTests: XCTestCase {
    func testPregameIsOnlyTheNextHourAndLaterGamesMoveIntoItAsTimePasses() {
        let now = Date(timeIntervalSince1970: 1_793_417_400)
        let team = SportsTeam(id: "1", name: "Team", abbreviation: "T", logo: "")
        func game(_ seconds: TimeInterval?, state: String = "pre") -> SportsGame {
            SportsGame(eventID: "scheduled", league: .nba, date: seconds.map { now.addingTimeInterval($0) }, state: state,
                       status: "Scheduled", home: team, away: team, venue: "", broadcasts: "", link: "")
        }
        XCTAssertEqual(game(0).scheduledPhase(at: now), .pregame)
        XCTAssertEqual(game(3600).scheduledPhase(at: now), .pregame)
        XCTAssertEqual(game(3601).scheduledPhase(at: now), .upcoming)
        XCTAssertEqual(game(86400).scheduledPhase(at: now), .upcoming)
        XCTAssertEqual(game(nil).scheduledPhase(at: now), .upcoming)
        XCTAssertNil(game(-1).scheduledPhase(at: now))
        XCTAssertNil(game(30, state: "in").scheduledPhase(at: now))
        XCTAssertNil(game(30, state: "post").scheduledPhase(at: now))
        XCTAssertEqual(game(3700).scheduledPhase(at: now.addingTimeInterval(100)), .pregame)
    }
}
