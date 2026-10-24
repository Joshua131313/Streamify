import Foundation
import XCTest
@testable import Streamify

final class SportsMidnightScheduleTests: XCTestCase {
    func testSuccessfulBackendCarriesOnlyYesterdayLiveUsingAdjacentCoverage() async throws {
        let calendar = try localCalendar("America/Toronto")
        let now = try instant("2026-10-24T04:05:00Z")
        let yesterday = "2026-10-24T03:30:00Z"
        let fixture = try MidnightScheduleFixture(backend: [
            backendGame("overnight", date: yesterday, state: "in"),
            backendGame("today", date: "2026-10-24T20:00:00Z", state: "pre"),
            backendGame("previous-final", date: yesterday, state: "post"),
            backendGame("previous-pre", date: yesterday, state: "pre"),
            backendGame("too-old", date: "2026-10-23T03:30:00Z", state: "in"),
            backendGame("future", date: "2026-10-25T05:00:00Z", state: "in"),
            backendGame("finished", date: yesterday, state: "post"),
            backendGame("finished", date: yesterday, state: "in")
        ])
        let service = SportsService(backend: "https://midnight.example", session: fixture.session, calendar: calendar, now: { now })
        let result = try await service.schedule(leagues: [.nba], day: now)
        XCTAssertEqual(result.games.map(\.eventID), ["overnight", "today"])
        XCTAssertFalse(result.partial)
        XCTAssertEqual(fixture.requests.count, 1, "A successful backend must retain its single range request.")
        let request = try XCTUnwrap(fixture.requests.first?.url)
        XCTAssertEqual(query("start", in: request), "2026-10-24", "The backend's adjacent UTC feeds already cover yesterday locally.")
        XCTAssertEqual(query("end", in: request), "2026-10-24")
        let carried = try XCTUnwrap(result.games.first)
        XCTAssertEqual(SportsScheduleDayPolicy.markerDay(for: carried, now: now, calendar: calendar), calendar.startOfDay(for: now))
    }

    func testESPNReusesAdjacentDaysAndFinalStateDefeatsLaterStaleLiveCopy() async throws {
        let calendar = try localCalendar("America/Toronto")
        let now = try instant("2026-10-24T04:05:00Z")
        let yesterday = "2026-10-24T03:30:00Z"
        let fixture = try MidnightScheduleFixture(scoreboards: [
            "20261023": [espnGame("overnight", date: yesterday, state: "in", score: "20"),
                         espnGame("finished", date: yesterday, state: "in")],
            "20261024": [espnGame("overnight", date: yesterday, state: "in", score: "21"),
                         espnGame("finished", date: yesterday, state: "post"),
                         espnGame("today", date: "2026-10-24T20:00:00Z", state: "pre")],
            "20261025": [espnGame("overnight", date: yesterday, state: "in", score: "22"),
                         espnGame("finished", date: yesterday, state: "in"),
                         espnGame("future", date: "2026-10-25T20:00:00Z", state: "pre")]
        ])
        let service = SportsService(session: fixture.session, calendar: calendar, now: { now })
        let result = try await service.schedule(leagues: [.nba], day: now)
        XCTAssertEqual(result.games.map(\.eventID), ["overnight", "today"])
        XCTAssertEqual(result.games.first?.home.score, "22", "Later responses refresh a duplicate that remains live.")
        XCTAssertEqual(fixture.requests.compactMap(\.url).compactMap { query("dates", in: $0) }, ["20261023", "20261024", "20261025"])
        XCTAssertFalse(result.partial)
    }

    func testWesternEveningBackendRangeRespectsUTCMinimumAndStillCarriesLive() async throws {
        let calendar = try localCalendar("America/Toronto")
        let now = try instant("2026-10-24T02:00:00Z") // Oct 23 at 22:00 locally.
        let fixture = try MidnightScheduleFixture(backend: [
            backendGame("overnight", date: "2026-10-23T02:00:00Z", state: "in")
        ])
        let result = try await SportsService(backend: "https://midnight.example", session: fixture.session,
            calendar: calendar, now: { now }).schedule(leagues: [.nba], day: now)
        XCTAssertEqual(result.games.map(\.eventID), ["overnight"])
        XCTAssertEqual(fixture.requests.count, 1)
        let request = try XCTUnwrap(fixture.requests.first?.url)
        XCTAssertEqual(query("start", in: request), "2026-10-23", "The API rejects Oct 22 here; its adjacent feeds still cover that local day.")
        XCTAssertEqual(query("end", in: request), "2026-10-23")
    }

    func testPartialBackendDoesNotResurrectFinishedGameWhenESPNFallbackIsStale() async throws {
        let calendar = try localCalendar("America/Toronto")
        let now = try instant("2026-10-24T04:05:00Z")
        let yesterday = "2026-10-24T03:30:00Z"
        let fixture = try MidnightScheduleFixture(backend: [backendGame("finished", date: yesterday, state: "post")],
            backendFailedDates: ["2026-10-24"], scoreboards: [
                "20261023": [espnGame("finished", date: yesterday, state: "in")],
                "20261024": [espnGame("finished", date: yesterday, state: "in")],
                "20261025": []
            ])
        let service = SportsService(backend: "https://midnight.example", session: fixture.session, calendar: calendar, now: { now })
        let result = try await service.schedule(leagues: [.nba], day: now)
        XCTAssertTrue(result.games.isEmpty)
        XCTAssertEqual(fixture.requests.count, 4)
    }

    func testFutureDateRemainsStrictInBackendAndESPN() async throws {
        let calendar = try localCalendar("America/Toronto")
        let now = try instant("2026-10-24T04:05:00Z")
        let tomorrow = try instant("2026-10-25T04:00:00Z")
        let backend = try MidnightScheduleFixture(backend: [
            backendGame("today-live", date: "2026-10-24T22:00:00Z", state: "in"),
            backendGame("tomorrow", date: "2026-10-25T20:00:00Z", state: "pre")
        ])
        let backendResult = try await SportsService(backend: "https://midnight.example", session: backend.session,
            calendar: calendar, now: { now }).schedule(leagues: [.nba], day: tomorrow)
        XCTAssertEqual(backendResult.games.map(\.eventID), ["tomorrow"])
        let request = try XCTUnwrap(backend.requests.first?.url)
        XCTAssertEqual(query("start", in: request), "2026-10-25")
        XCTAssertEqual(query("end", in: request), "2026-10-25")
        let espn = try MidnightScheduleFixture(scoreboards: [
            "20261024": [espnGame("today-live", date: "2026-10-24T22:00:00Z", state: "in")],
            "20261025": [espnGame("tomorrow", date: "2026-10-25T20:00:00Z", state: "pre")],
            "20261026": []
        ])
        let espnResult = try await SportsService(session: espn.session, calendar: calendar, now: { now })
            .schedule(leagues: [.nba], day: tomorrow)
        XCTAssertEqual(espnResult.games.map(\.eventID), ["tomorrow"])
    }

    func testCarryoverUsesLocalCalendarDaysAcrossBothDSTChanges() async throws {
        let calendar = try localCalendar("America/Toronto")
        for sample in [
            ("2026-11-02T05:10:00Z", "2026-11-01T04:30:00Z", "2026-11-01T03:30:00Z", "2026-11-02"),
            ("2026-03-09T04:10:00Z", "2026-03-08T05:30:00Z", "2026-03-08T04:30:00Z", "2026-03-09")
        ] {
            let now = try instant(sample.0)
            let fixture = try MidnightScheduleFixture(backend: [
                backendGame("overnight", date: sample.1, state: "in"),
                backendGame("too-old", date: sample.2, state: "in")
            ])
            let result = try await SportsService(backend: "https://midnight.example", session: fixture.session,
                calendar: calendar, now: { now }).schedule(leagues: [.nba], day: now)
            XCTAssertEqual(result.games.map(\.eventID), ["overnight"])
            XCTAssertEqual(query("start", in: try XCTUnwrap(fixture.requests.first?.url)), sample.3)
        }
    }

    func testPositiveTimezoneAndNonMidnightSelectionStillFetchPreviousLocalDay() async throws {
        let calendar = try localCalendar("Pacific/Kiritimati")
        let now = try instant("2026-10-24T08:00:00Z") // Oct 24 at 22:00, UTC+14.
        let fixture = try MidnightScheduleFixture(scoreboards: [
            "20261022": [espnGame("overnight", date: "2026-10-22T10:30:00Z", state: "in")],
            "20261023": [], "20261024": []
        ])
        let result = try await SportsService(session: fixture.session, calendar: calendar, now: { now })
            .schedule(leagues: [.nba], day: now)
        XCTAssertEqual(result.games.map(\.eventID), ["overnight"])
        XCTAssertEqual(fixture.requests.compactMap(\.url).compactMap { query("dates", in: $0) }, ["20261022", "20261023", "20261024"])
        let backend = try MidnightScheduleFixture(backend: [backendGame("overnight", date: "2026-10-22T10:30:00Z", state: "in")])
        let backendResult = try await SportsService(backend: "https://midnight.example", session: backend.session,
            calendar: calendar, now: { now }).schedule(leagues: [.nba], day: now)
        XCTAssertEqual(backendResult.games.map(\.eventID), ["overnight"])
        let request = try XCTUnwrap(backend.requests.first?.url)
        XCTAssertEqual(query("start", in: request), "2026-10-23", "UTC+14 needs one extra UTC feed for the preceding local day's first hours.")
        XCTAssertEqual(query("end", in: request), "2026-10-24")
    }

    func testMidnightSelectionAdvancesTodayButPreservesAnExplicitFutureDate() throws {
        let calendar = try localCalendar("America/Toronto")
        let before = try instant("2026-10-24T03:59:00Z")
        let after = try instant("2026-10-24T04:01:00Z")
        let future = try instant("2026-10-27T04:00:00Z")
        XCTAssertEqual(SportsScheduleDayPolicy.selectedDay(calendar.startOfDay(for: before), now: after, calendar: calendar), calendar.startOfDay(for: after))
        XCTAssertEqual(SportsScheduleDayPolicy.selectedDay(future, now: after, calendar: calendar), future)
    }

    private func instant(_ value: String) throws -> Date { try XCTUnwrap(SportsService.parseDate(value)) }
    private func localCalendar(_ identifier: String) throws -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return value
    }
    private func query(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
    private func backendGame(_ id: String, date: String, state: String) -> [String: Any] {
        ["id": id, "date": date, "state": state, "status": state,
         "homeTeam": ["id": "home", "name": "Home", "abbreviation": "HOM", "score": "20"],
         "awayTeam": ["id": "away", "name": "Away", "abbreviation": "AWY", "score": "19"]]
    }
    private func espnGame(_ id: String, date: String, state: String, score: String = "20") -> [String: Any] {
        ["id": id, "date": date, "competitions": [[
            "status": ["type": ["state": state, "shortDetail": state]],
            "competitors": [
                ["homeAway": "home", "score": score, "team": ["id": "home", "displayName": "Home", "abbreviation": "HOM"]],
                ["homeAway": "away", "score": "19", "team": ["id": "away", "displayName": "Away", "abbreviation": "AWY"]]
            ]
        ]]]
    }
}

private final class MidnightScheduleFixture {
    let session: URLSession
    private let identifier = UUID().uuidString
    private let scenario: MidnightScheduleScenario
    var requests: [URLRequest] { scenario.requests }
    init(backend: [[String: Any]]? = nil, backendFailedDates: [String] = [], scoreboards: [String: [[String: Any]]] = [:]) throws {
        let backendData = try backend.map { try JSONSerialization.data(withJSONObject: ["games": $0, "failedDates": backendFailedDates]) }
        let scoreboardsData = try scoreboards.mapValues { try JSONSerialization.data(withJSONObject: ["events": $0]) }
        scenario = MidnightScheduleScenario(backend: backendData, scoreboards: scoreboardsData)
        MidnightScheduleProtocol.register(scenario, identifier: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MidnightScheduleProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Midnight-Test": identifier]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); MidnightScheduleProtocol.unregister(identifier) }
}

private final class MidnightScheduleScenario {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    let backend: Data?
    let scoreboards: [String: Data]
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(backend: Data?, scoreboards: [String: Data]) { self.backend = backend; self.scoreboards = scoreboards }
    func response(for request: URLRequest) -> Data? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        guard let url = request.url else { return nil }
        if url.host == "midnight.example", url.path == "/api/schedule" { return backend }
        guard url.host == "site.api.espn.com", url.path == "/apis/site/v2/sports/basketball/nba/scoreboard",
              let date = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "dates" })?.value else { return nil }
        return scoreboards[date]
    }
}

private final class MidnightScheduleProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var scenarios: [String: MidnightScheduleScenario] = [:]
    static func register(_ scenario: MidnightScheduleScenario, identifier: String) { lock.lock(); defer { lock.unlock() }; scenarios[identifier] = scenario }
    static func unregister(_ identifier: String) { lock.lock(); defer { lock.unlock() }; scenarios.removeValue(forKey: identifier) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-Streamify-Midnight-Test").flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        guard let scenario, let data = scenario.response(for: request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
