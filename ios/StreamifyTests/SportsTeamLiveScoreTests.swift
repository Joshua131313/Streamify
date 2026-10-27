import XCTest
@testable import Streamify

final class SportsTeamLiveScoreTests: XCTestCase {
    func testTeamSeasonFeedMissingLiveScoresIsFilledFromTheCurrentGameWithoutDroppingUpcomingGames() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TeamLiveScoreProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = SportsService(session: session)
        let profile = try await service.profile(.init(league: .nba, team: .init(id: "1", name: "Home", abbreviation: "HOM", logo: "")))
        let live = try XCTUnwrap(profile.games.first { $0.eventID == "401123456" })
        XCTAssertEqual(live.home.score, "71")
        XCTAssertEqual(live.away.score, "68")
        XCTAssertEqual(live.status, "Q3 8:42")
        XCTAssertTrue(profile.games.contains { $0.eventID == "401123457" && $0.state == "pre" })
    }
}

private final class TeamLiveScoreProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        func event(scores: Bool, upcoming: Bool = false) -> [String: Any] {
            func team(home: Bool) -> [String: Any] {
                var row: [String: Any] = ["homeAway": home ? "home" : "away", "team": ["id": home ? "1" : "2", "displayName": home ? "Home" : "Away", "abbreviation": home ? "HOM" : "AWY"]]
                if scores { row["score"] = home ? "71" : "68" }
                return row
            }
            return ["id": upcoming ? "401123457" : "401123456", "date": upcoming ? "2026-10-29T23:00:00Z" : "2026-10-26T23:00:00Z",
                "competitions": [["competitors": [team(home: false), team(home: true)], "status": ["period": 3, "displayClock": "8:42", "type": ["state": upcoming ? "pre" : "in", "shortDetail": upcoming ? "Scheduled" : "Q3 8:42"]]]]]
        }
        guard let url = request.url else { return }
        let value: [String: Any]
        if url.path.hasSuffix("/schedule") { value = ["events": [event(scores: false), event(scores: false, upcoming: true)]] }
        else if url.path.hasSuffix("/summary") { value = ["header": event(scores: true), "situation": ["possession": "1"]] }
        else if url.path.hasSuffix("/roster") { value = ["athletes": []] }
        else { value = ["team": ["id": "1", "displayName": "Home", "abbreviation": "HOM"]] }
        let data = try! JSONSerialization.data(withJSONObject: value)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
