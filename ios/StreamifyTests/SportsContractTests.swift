import Foundation
import XCTest
@testable import Streamify

final class SportsContractTests: XCTestCase {
    func testWatchResolvesFreshSourceAddressesWhileKeepingDiscoveryResultsWarm() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamDiscoveryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        StreamDiscoveryProtocol.state.reset()
        let service = SportsService(session: session)
        var event = SportsFixture.event
        event["date"] = ISO8601DateFormatter().string(from: Date())
        let game = try XCTUnwrap(service.parseGame(event, league: .nba))
        let first = try await service.streams(game)
        let second = try await service.streams(game)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertNotEqual(first.first?.url, second.first?.url,
            "Another Watch must not reuse a source address from the previous connection.")
        XCTAssertEqual(StreamDiscoveryProtocol.state.calls, [1, 2],
            "Keep the match catalog cached, but fetch the selected stream's current address each time.")
    }
    func testESPNDecodesMixedScoreShapesAndShortUTCDate() throws {
        let service = SportsService()
        let game = try XCTUnwrap(service.parseGame(SportsFixture.event, league: .nba))
        XCTAssertEqual(game.id, "nba:fixture-game")
        XCTAssertEqual(game.home.name, "Boston Celtics")
        XCTAssertEqual(game.away.name, "Los Angeles Lakers")
        XCTAssertEqual(game.home.score, "115")
        XCTAssertEqual(game.away.score, "110")
        XCTAssertTrue(game.isLive)
        XCTAssertEqual(game.date, SportsService.parseDate("2026-10-23T00:30:00Z"))
        XCTAssertEqual(SportsService.parseDate("2026-10-23T00:30Z"), SportsService.parseDate("2026-10-22T20:30:00-04:00"))
        XCTAssertNotNil(SportsService.parseDate("2026-10-23T00:30:00.123Z"))
        XCTAssertNil(service.parseGame(["id": "bad", "competitions": []], league: .nba))
    }

    func testScheduleUsesSelectedLocalDayAndDeduplicatesAdjacentUTCFeeds() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SportsFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = SportsService(session: session, calendar: calendar)
        let result = try await service.schedule(leagues: [.nba], day: day)
        XCTAssertFalse(result.partial)
        XCTAssertEqual(result.games.map(\.eventID), ["fixture-game"], "00:30 UTC belongs to the previous Toronto day; duplicate UTC feeds must produce one card.")
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(result.games.first?.date), inSameDayAs: day))
    }

    func testStreamMatchRequiresBothFullTeamsRecentDateCorrectSportAndSources() throws {
        let game = try XCTUnwrap(SportsService().parseGame(SportsFixture.event, league: .nba))
        let now = try XCTUnwrap(SportsService.parseDate("2026-10-23T00:30:00Z"))
        func match(_ id: String, home: String = "Boston Celtics", away: String = "LA Lakers", category: String = "basketball", age: TimeInterval = 0, sources: Bool = true) -> [String: Any] {
            ["id": id, "title": "\(away) at \(home)", "category": category, "date": now.addingTimeInterval(-age).timeIntervalSince1970 * 1000,
             "teams": ["home": ["name": home], "away": ["name": away]], "sources": sources ? [["source": "alpha", "id": id]] : []]
        }
        let rejected = [match("wrong-sport", category: "hockey"), match("one-team", away: "Los Angeles Clippers"),
                        match("old", age: 48 * 3600), match("no-sources", sources: false)]
        XCTAssertNil(SportsService.matchingStreamMatch(rejected, game: game, now: now))
        let matched = try XCTUnwrap(SportsService.matchingStreamMatch(rejected + [match("correct")], game: game, now: now))
        XCTAssertEqual(matched["id"] as? String, "correct", "LA normalization must still require the full opponent.")
        let reversed = match("reversed", home: "Los Angeles Lakers", away: "Boston Celtics")
        XCTAssertEqual(SportsService.matchingStreamMatch([reversed], game: game, now: now)?["id"] as? String, "reversed")
    }

    func testDownloadAttemptIdentityRejectsLateCancelledAndRetriedCallbacks() throws {
        var item = DownloadItem(id: UUID(), title: "Fixture", source: "https://example.com/video.mp4", createdAt: Date(), status: .downloading)
        item.taskIdentifier = 17
        XCTAssertTrue(item.acceptsCallback(taskIdentifier: 17))
        item.status = .cancelled
        XCTAssertFalse(item.acceptsCallback(taskIdentifier: 17), "A finished file arriving after Cancel must not restore the cancelled entry.")
        item.status = .downloading
        item.taskIdentifier = 18
        XCTAssertFalse(item.acceptsCallback(taskIdentifier: 17), "A previous attempt must not overwrite the retried download.")
        XCTAssertTrue(item.acceptsCallback(taskIdentifier: 18))
        let restored = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
        XCTAssertTrue(restored.acceptsCallback(taskIdentifier: 18), "Background relaunches must retain the active task identity.")
        item.status = .completed
        XCTAssertFalse(item.acceptsCallback(taskIdentifier: 18))
    }
}

private enum SportsFixture {
    static var event: [String: Any] {
        ["id": "fixture-game", "date": "2026-10-23T00:30Z", "competitions": [[
            "status": ["type": ["state": "in", "shortDetail": "4th · 0:12"]],
            "venue": ["fullName": "Fixture Arena"], "broadcasts": [["names": ["ESPN"]]],
            "competitors": [
                ["homeAway": "home", "score": 115, "team": ["id": "2", "displayName": "Boston Celtics", "abbreviation": "BOS", "logo": "https://example.com/bos.png"]],
                ["homeAway": "away", "score": ["displayValue": "110"], "team": ["id": "13", "displayName": "Los Angeles Lakers", "abbreviation": "LAL", "logos": [["href": "https://example.com/lal.png"]]]]
            ]
        ]]]
    }
    static var scoreboard: Data {
        var nextDay = event
        nextDay["id"] = "next-local-day"
        nextDay["date"] = "2026-10-23T18:00Z"
        return (try? JSONSerialization.data(withJSONObject: ["events": [event, nextDay]])) ?? Data()
    }
}

private final class SportsFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "site.api.espn.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "/apis/site/v2/sports/basketball/nba/scoreboard",
              let date = parts.queryItems?.first(where: { $0.name == "dates" })?.value,
              ["20261021", "20261022", "20261023"].contains(date),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: SportsFixture.scoreboard)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class StreamDiscoveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var matches = 0
    private var sources = 0
    var calls: [Int] { lock.lock(); defer { lock.unlock() }; return [matches, sources] }
    func reset() { lock.lock(); defer { lock.unlock() }; matches = 0; sources = 0 }
    func data(for url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let object: [[String: Any]]
        if url.path == "/api/matches/all" {
            matches += 1
            object = [["id": "fixture", "title": "Los Angeles Lakers at Boston Celtics", "category": "basketball",
                "date": Date().timeIntervalSince1970 * 1000,
                "teams": ["home": ["name": "Boston Celtics"], "away": ["name": "Los Angeles Lakers"]],
                "sources": [["source": "alpha", "id": "fixture"]]]]
        } else {
            sources += 1
            object = [["embedUrl": "https://example.com/player?connection=\(sources)", "streamNo": 1, "language": "English", "hd": true]]
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

private final class StreamDiscoveryProtocol: URLProtocol {
    static let state = StreamDiscoveryState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "streamed.pk" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            let data = try Self.state.data(for: url)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
