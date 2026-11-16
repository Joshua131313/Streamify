import Foundation
import XCTest
@testable import Streamify

final class SportsPostgameTests: XCTestCase {
    func testFinalOnlyPermitsWatchUntilExclusiveThirtyMinuteCutoff() {
        let end = Date(timeIntervalSince1970: 2_000_000_000)
        let final = game(state: "post", end: end)
        XCTAssertTrue(final.isFinal)
        XCTAssertFalse(final.canWatch(at: end.addingTimeInterval(-1)))
        XCTAssertTrue(final.canWatch(at: end))
        XCTAssertTrue(final.canWatch(at: end.addingTimeInterval(1799)))
        XCTAssertFalse(final.canWatch(at: end.addingTimeInterval(1800)))
        XCTAssertFalse(game(state: "post", start: end).canWatch(at: end))
        XCTAssertFalse(game(state: "post", end: end, status: "Cancelled").canWatch(at: end))
        XCTAssertFalse(game(state: "post", end: end, start: end.addingTimeInterval(1)).canWatch(at: end))
    }

    func testOnlyRecentObservedTransitionIsPersistedAndCanonicalEndWins() throws {
        let suite = "streamify.postgame.test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SportsPostgameHistory(defaults: defaults)
        let end = Date(timeIntervalSince1970: 2_000_000_000)
        let start = end.addingTimeInterval(-3600)
        let live = game(state: "in", start: start)
        let final = game(state: "post", start: start)
        let stale = game(id: "stale", state: "in", start: start)
        _ = history.observe([stale], at: end.addingTimeInterval(-601))
        _ = history.observe([live], at: end.addingTimeInterval(-60))
        XCTAssertNil(history.observe([game(id: "unknown", state: "post", start: start)], at: end)[0].endedAt)
        XCTAssertNil(history.observe([game(id: "stale", state: "post", start: start)], at: end)[0].endedAt)
        XCTAssertEqual(history.observe([final], at: end)[0].endedAt, end)

        let relaunched = SportsPostgameHistory(defaults: defaults)
        XCTAssertEqual(relaunched.observe([final], at: end.addingTimeInterval(120))[0].endedAt, end)
        let canonical = end.addingTimeInterval(-35)
        var corrected = final
        corrected.endedAt = canonical
        XCTAssertEqual(relaunched.observe([corrected], at: end.addingTimeInterval(121))[0].endedAt, canonical)
        XCTAssertFalse(relaunched.applyingKnownEnd(to: live).canWatch(at: canonical.addingTimeInterval(1800)))
        XCTAssertNil(relaunched.observe([game(state: "post", start: start.addingTimeInterval(-3600))], at: end.addingTimeInterval(122))[0].endedAt)
    }

    func testDetailEndRequiresACompletedEventAndUsesWallClock() throws {
        let value = "2026-11-16T01:12:04Z"
        let end = try XCTUnwrap(SportsService.parseDate(value))
        let final = game(state: "post", end: end)
        let header = ["competitions": [["status": ["type": ["name": "STATUS_FINAL"]]]]]
        let summary: [String: Any] = ["header": header, "meta": ["lastPlayWallClock": value]]
        XCTAssertEqual(SportsService.summaryEnd(summary, game: final), end)
        XCTAssertNil(SportsService.summaryEnd(summary, game: game(state: "in", start: end)))
        XCTAssertNil(SportsService.summaryEnd(["header": header, "plays": [["text": "Timeout", "wallclock": value]]], game: final))
        XCTAssertEqual(SportsService.summaryEnd(["header": header, "drives": ["previous": [["plays": [["text": "End of Game", "wallclock": value]]]]]], game: final), end)
    }

    func testAfterMidnightTodayIncludesOnlyRecentFinalFromPriorDay() throws {
        let now = try XCTUnwrap(SportsService.parseDate("2026-11-16T00:15:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let old = game(id: "expired", state: "post", end: now.addingTimeInterval(-1800))
        let recent = game(id: "recent", state: "post", end: now.addingTimeInterval(-1000))
        XCTAssertEqual(SportsScheduleDayPolicy.games([old, recent], for: now, now: now, calendar: calendar).map(\.id), [recent.id])
    }

    func testFinishedMatchoraListingsStillRequireExactMatchAndUnexpiredWindow() {
        let end = Date(timeIntervalSince1970: 2_000_000_000)
        let kickoff = end.addingTimeInterval(-10_800)
        let final = game(state: "post", end: end, start: kickoff)
        var event: [String: Any] = ["id": "999", "home": "Home", "away": "Away", "sport": "Basketball", "league": "NBA",
                                    "kickoff": kickoff.timeIntervalSince1970, "finished": true]
        XCTAssertTrue(MatchoraProvider.matches(event, game: final, now: end.addingTimeInterval(60)))
        XCTAssertFalse(MatchoraProvider.matches(event, game: final, now: end.addingTimeInterval(1800)))
        event["away"] = "Another team"
        XCTAssertFalse(MatchoraProvider.matches(event, game: final, now: end.addingTimeInterval(60)))
    }

    @MainActor func testPlayingAndQueuedTileSurviveFinalWithoutReplacingSource() async throws {
        let now = Date()
        let id = UUID().uuidString
        let kickoff = now.addingTimeInterval(-3 * 3600)
        let live = game(id: id, state: "in", start: kickoff)
        var latest = game(id: id, state: "post", end: now.addingTimeInterval(-60), start: kickoff)
        let primary = SportsStream(title: "Primary", url: try XCTUnwrap(URL(string: "https://example.test/primary")))
        let alternate = SportsStream(title: "Alternate", url: try XCTUnwrap(URL(string: "https://example.test/alternate")))
        let session = SportsPlaybackSession(loadSchedule: { _ in SportsSchedule(games: [latest], failedLeagues: [], partial: false) })
        let queue = SportsWatchQueue()
        let tile = SportsStream(title: "Fixture", url: primary.url, alternatives: [primary, alternate])
        queue.add(tile, game: live)
        session.play(title: "Fixture", url: primary.url, sources: [primary, alternate], game: live)
        let identity = try XCTUnwrap(session.item?.id)

        await session.refreshLiveGames()
        queue.updateGames([latest])
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, primary.url)
        XCTAssertTrue(session.item?.game?.isFinal == true)
        XCTAssertTrue(queue.canStart(tile))
        XCTAssertEqual(queue.streams.map(\.id), [tile.id])
        XCTAssertEqual(session.liveGames.map(\.id), [latest.id])

        latest.endedAt = now.addingTimeInterval(-1801)
        await session.refreshLiveGames()
        queue.updateGames([latest])
        session.selectSource(alternate)
        session.reloadCurrent()
        queue.selectSource(streamID: tile.id, url: alternate.url)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, primary.url)
        XCTAssertEqual(session.reload, 0)
        XCTAssertEqual(queue.streams.first?.url, primary.url)
        XCTAssertTrue(session.liveGames.isEmpty)
        queue.removeExpired()
        XCTAssertTrue(queue.streams.isEmpty, "An expired tile cannot start again when MultiWatch reopens.")
    }

    private func game(id: String = "100", state: String, end: Date? = nil, start: Date? = nil, status: String = "Final") -> SportsGame {
        SportsGame(eventID: id, league: .nba, date: start ?? end?.addingTimeInterval(-3 * 3600), state: state, status: status,
            home: SportsTeam(id: "2", name: "Home", abbreviation: "HOM", logo: "", score: "100"),
            away: SportsTeam(id: "1", name: "Away", abbreviation: "AWY", logo: "", score: "98"),
            venue: "", broadcasts: "", link: "", endedAt: end)
    }
}
