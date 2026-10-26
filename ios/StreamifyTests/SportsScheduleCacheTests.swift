import XCTest
@testable import Streamify

@MainActor final class SportsScheduleCacheTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func game(_ league: SportsLeague) -> SportsGame {
        SportsGame(eventID: "one", league: league, date: day, state: "in", status: "Q2",
            home: SportsTeam(id: "h", name: "Home", abbreviation: "H", logo: ""),
            away: SportsTeam(id: "a", name: "Away", abbreviation: "A", logo: ""), venue: "", broadcasts: "", link: "")
    }
    func testAllLeaguesSeedsEverySubsetIncludingKnownEmptyWithoutExtendingFreshness() throws {
        let cache = SportsScheduleCache()
        let schedule = SportsSchedule(games: [game(.nfl), game(.nba)], failedLeagues: [], partial: false)
        cache.store(schedule, leagues: SportsLeague.allCases, day: day, backend: "a", calendar: calendar, fetchedAt: day)
        for league in [SportsLeague.nfl, .nba, .ncaaf, .nfl, .nba] {
            let result = try XCTUnwrap(cache.snapshot(leagues: [league], day: day, backend: "a", calendar: calendar, now: day.addingTimeInterval(5)))
            XCTAssertTrue(result.fresh)
            XCTAssertEqual(result.games.map(\.id), schedule.games.filter { $0.league == league }.map(\.id))
        }
        XCTAssertTrue(try XCTUnwrap(cache.snapshot(leagues: [.nba], day: day, backend: "a", calendar: calendar, now: day.addingTimeInterval(60))).fresh)
        let stale = try XCTUnwrap(cache.snapshot(leagues: [.nfl], day: day, backend: "a", calendar: calendar, now: day.addingTimeInterval(121)))
        XCTAssertFalse(stale.fresh)
        XCTAssertEqual(stale.games.count, 1, "Stale cards remain visible during a background refresh.")
    }
    func testUnknownFailedDayBackendAndTimezoneAreNeverMistakenForFetchedEmpty() {
        let cache = SportsScheduleCache()
        cache.store(SportsSchedule(games: [game(.nfl)], failedLeagues: [.nba], partial: true),
            leagues: [.nfl, .nba], day: day, backend: "a", calendar: calendar, fetchedAt: day)
        XCTAssertNil(cache.snapshot(leagues: [.nba], day: day, backend: "a", calendar: calendar, now: day))
        XCTAssertNil(cache.snapshot(leagues: [.nfl, .nba], day: day, backend: "a", calendar: calendar, now: day))
        XCTAssertNil(cache.snapshot(leagues: [.nfl], day: day.addingTimeInterval(86400), backend: "a", calendar: calendar, now: day))
        XCTAssertNil(cache.snapshot(leagues: [.nfl], day: day, backend: "b", calendar: calendar, now: day))
        var otherZone = calendar; otherZone.timeZone = TimeZone(identifier: "America/Toronto")!
        XCTAssertNil(cache.snapshot(leagues: [.nfl], day: day, backend: "a", calendar: otherZone, now: day))
    }
}
