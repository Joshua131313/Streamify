import Foundation
import XCTest
@testable import Streamify

final class CollegeFootballTests: XCTestCase {
    func testCollegeLeagueUsesFootballEndpointAndAmericanFootballStreams() {
        XCTAssertEqual(SportsLeague.ncaaf.title, "NCAAF")
        XCTAssertEqual(SportsLeague.ncaaf.endpoint, "https://site.api.espn.com/apis/site/v2/sports/football/college-football")
        XCTAssertEqual(SportsLeague.ncaaf.category, "american-football")
        XCTAssertEqual(SportsLeague.ncaaf.scoreboardParameters.count, 2)
    }

    func testScheduleMergesFBSAndFCSWithoutDuplicatesAndKeepsLocalDate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollegeFootballFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        // The existing optional backend does not support college football. Its empty
        // response must not suppress the NCAA ESPN feeds.
        let service = SportsService(backend: "https://college-backend-unsupported.test", session: session, calendar: calendar)
        let schedule = try await service.schedule(leagues: [.ncaaf], day: day)
        XCTAssertFalse(schedule.partial)
        XCTAssertEqual(Set(schedule.games.map(\.eventID)), ["fbs", "fcs", "shared"])
        XCTAssertEqual(schedule.games.count, 3)
        XCTAssertTrue(schedule.games.allSatisfy { $0.league == .ncaaf && $0.date.map { calendar.isDate($0, inSameDayAs: day) } == true })
    }

    func testCollegeStreamsRequireBothExactSchoolAliasesAndCorrectKickoff() throws {
        let service = SportsService()
        let game = try XCTUnwrap(service.parseGame(CollegeFootballFixture.event(id: "fbs"), league: .ncaaf))
        let now = try XCTUnwrap(game.date)
        XCTAssertTrue(game.home.streamNames.contains("Alabama"))
        func match(_ id: String, home: String = "Alabama", away: String = "Georgia", category: String = "american-football", offset: TimeInterval = 0, sources: Bool = true) -> [String: Any] {
            ["id": id, "title": "Alabama vs Georgia", "category": category,
             "date": now.addingTimeInterval(offset).timeIntervalSince1970 * 1000,
             "teams": ["home": ["name": home], "away": ["name": away]],
             "sources": sources ? [["source": "alpha", "id": id]] : []]
        }
        let rejected = [match("different-school", home: "Alabama State"), match("one-team", away: "Georgia Tech"),
                        match("mascot-only", home: "Crimson Tide"), match("wrong-sport", category: "football"),
                        match("wrong-kickoff", offset: 7 * 3600), match("no-sources", sources: false)]
        XCTAssertNil(SportsService.matchingStreamMatch(rejected, game: game, now: now))
        XCTAssertEqual(SportsService.matchingStreamMatch(rejected + [match("correct")], game: game, now: now)?["id"] as? String, "correct")
        XCTAssertEqual(SportsService.matchingStreamMatch([match("reversed", home: "Georgia Bulldogs", away: "Alabama Crimson Tide")], game: game, now: now)?["id"] as? String, "reversed")
        var titleOnly = match("title-only")
        titleOnly.removeValue(forKey: "teams")
        XCTAssertEqual(SportsService.matchingStreamMatch([titleOnly], game: game, now: now)?["id"] as? String, "title-only")
        titleOnly["title"] = "Alabama State vs Georgia"
        XCTAssertNil(SportsService.matchingStreamMatch([titleOnly], game: game, now: now))
    }
}

private enum CollegeFootballFixture {
    static func event(id: String, date: String = "2026-10-23T00:30:00Z") -> [String: Any] {
        ["id": id, "date": date, "competitions": [[
            "status": ["type": ["state": "in", "shortDetail": "Q2"]],
            "competitors": [
                ["homeAway": "home", "score": "14", "team": ["id": "333", "displayName": "Alabama Crimson Tide", "shortDisplayName": "Alabama", "location": "Alabama", "name": "Crimson Tide", "abbreviation": "ALA"]],
                ["homeAway": "away", "score": "7", "team": ["id": "61", "displayName": "Georgia Bulldogs", "shortDisplayName": "Georgia", "location": "Georgia", "name": "Bulldogs", "abbreviation": "UGA"]]
            ]
        ]]]
    }
}

private final class CollegeFootballFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var body: [String: Any] = ["games": []]
        if url.host == "site.api.espn.com" {
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let group = parts?.queryItems?.first { $0.name == "groups" }?.value
            guard url.path == "/apis/site/v2/sports/football/college-football/scoreboard", ["80", "81"].contains(group ?? "") else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            body = ["events": [CollegeFootballFixture.event(id: group == "80" ? "fbs" : "fcs"),
                               CollegeFootballFixture.event(id: "shared"),
                               CollegeFootballFixture.event(id: "next-day", date: "2026-10-23T18:00:00Z")]]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
