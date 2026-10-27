import Foundation
import XCTest
@testable import Streamify

final class SportsSourceAggregationTests: XCTestCase {
    func testADeadProviderDoesNotHideIndependentSourcesAndOrderingIsStable() throws {
        let primary = source("TimStreams", "https://one.fixture.test/video")
        let other = source("StreamFree", "https://two.fixture.test/video")
        let duplicate = source("Duplicate", primary.url.absoluteString)
        let values = try SportsService.mergedSourceResults([
            .init(provider: 3, streams: [], error: SportsServiceError.streamProviderUnavailable),
            .init(provider: 2, streams: [duplicate, other], error: nil),
            .init(provider: 0, streams: [primary], error: nil)
        ])
        XCTAssertEqual(values.map(\.title), ["TimStreams", "StreamFree"])
        XCTAssertEqual(values.map(\.url), [primary.url, other.url])
    }

    func testNoPublishedGameIsDifferentFromEveryProviderFailing() throws {
        XCTAssertTrue(try SportsService.mergedSourceResults([
            .init(provider: 0, streams: [], error: nil),
            .init(provider: 1, streams: [], error: URLError(.cannotFindHost))
        ]).isEmpty)
        XCTAssertThrowsError(try SportsService.mergedSourceResults([
            .init(provider: 1, streams: [], error: SportsServiceError.invalidResponse),
            .init(provider: 0, streams: [], error: URLError(.notConnectedToInternet))
        ])) { XCTAssertEqual(($0 as? URLError)?.code, .notConnectedToInternet) }
    }

    func testProviderDeadlineCancelsItsActualURLSessionRequest() async throws {
        HangingSportsSourceProtocol.state.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingSportsSourceProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://deadline.fixture.test/catalog")!)
        let began = Date()
        do {
            _ = try await SportsService.withSourceDeadline(seconds: 0.15) {
                _ = try await SportsSourceDocumentCache.shared.data(for: request, session: session, lifetime: 30)
                return []
            }
            XCTFail("A source that never responds must not hold Watch open.")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(began), 2)
        }
        XCTAssertTrue(HangingSportsSourceProtocol.state.started)
        for _ in 0..<40 where !HangingSportsSourceProtocol.state.stopped { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(HangingSportsSourceProtocol.state.stopped, "Timeout must cancel transport, not leave a detached catalog request running.")
    }

    func testLegacyBackoffIsTemporaryAndIsolatedFromOtherSessions() async {
        let health = SportsLegacySourceAvailability()
        let date = Date(timeIntervalSince1970: 100)
        await health.unavailable("session-a", now: date)
        let before = await health.allows("session-a", now: date.addingTimeInterval(1))
        let other = await health.allows("session-b", now: date.addingTimeInterval(1))
        let after = await health.allows("session-a", now: date.addingTimeInterval(31))
        XCTAssertFalse(before)
        XCTAssertTrue(other)
        XCTAssertTrue(after)
    }

    func testTeamIdentityDoesNotConfuseCitiesCollegeNamesOrDifferentLeagues() {
        let date = Date()
        func game(_ league: SportsLeague, home: SportsTeam, away: SportsTeam) -> SportsGame {
            SportsGame(eventID: "123", league: league, date: date, state: "in", status: "Live", home: home, away: away, venue: "", broadcasts: "", link: "")
        }
        let lakers = SportsTeam(id: "l", name: "Los Angeles Lakers", abbreviation: "LAL", logo: "", streamNames: ["Lakers", "Los Angeles"])
        let clippers = SportsTeam(id: "c", name: "Los Angeles Clippers", abbreviation: "LAC", logo: "", streamNames: ["Clippers", "Los Angeles"])
        let nba = game(.nba, home: lakers, away: clippers)
        XCTAssertTrue(SportsSourceIdentity.teamsMatch("NBA : LA Clippers vs Los Angeles Lakers", game: nba))
        XCTAssertFalse(SportsSourceIdentity.teamsMatch("Los Angeles vs Los Angeles", game: nba))
        XCTAssertFalse(SportsSourceIdentity.leagueMatches("WNBA", game: nba))
        let college = game(.ncaaf,
            home: SportsTeam(id: "a", name: "Alabama Crimson Tide", abbreviation: "ALA", logo: "", streamNames: ["Alabama"]),
            away: SportsTeam(id: "g", name: "Georgia Bulldogs", abbreviation: "UGA", logo: "", streamNames: ["Georgia"]))
        XCTAssertTrue(SportsSourceIdentity.teamsMatch("College Football : Georgia at Alabama", game: college))
        XCTAssertFalse(SportsSourceIdentity.teamsMatch("Alabama State vs Georgia", game: college))
        XCTAssertTrue(SportsSourceIdentity.sourceDateMatches(date, game: college, now: date))
        XCTAssertFalse(SportsSourceIdentity.sourceDateMatches(date.addingTimeInterval(-86400), game: college, now: date))
    }

    private func source(_ title: String, _ url: String) -> SportsStream { SportsStream(title: title, url: URL(string: url)!) }
}

private final class HangingSportsSourceState: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    private var didStop = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return didStop }
    func reset() { lock.lock(); defer { lock.unlock() }; didStart = false; didStop = false }
    func start() { lock.lock(); defer { lock.unlock() }; didStart = true }
    func stop() { lock.lock(); defer { lock.unlock() }; didStop = true }
}

private final class HangingSportsSourceProtocol: URLProtocol {
    static let state = HangingSportsSourceState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state.start() }
    override func stopLoading() { Self.state.stop() }
}
