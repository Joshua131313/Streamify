import Foundation
import XCTest
@testable import Streamify

final class FoxTrendProviderTests: XCTestCase {
    private let now = Date()
    private let path = "/event/m-texas-state-bobcats-vs-boise-state-broncos-1101"
    private var game: SportsGame {
        SportsGame(eventID: "401860908", league: .ncaaf, date: now, state: "in", status: "Live",
            home: SportsTeam(id: "68", name: "Boise State Broncos", abbreviation: "BOIS", logo: "", streamNames: ["Boise State"]),
            away: SportsTeam(id: "326", name: "Texas State Bobcats", abbreviation: "TXST", logo: "", streamNames: ["Texas State"]),
            venue: "", broadcasts: "", link: "")
    }
    private var entry: [String: Any] {
        ["t": "Texas State Bobcats vs Boise State Broncos", "g": "College Football", "u": path,
         "w": Int(now.timeIntervalSince1970 * 1000), "l": 1, "e": 0]
    }
    private func catalog(_ row: [String: Any]? = nil) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [row ?? entry])
        return "<script id='searchIndex' type='application/json'>" + String(decoding: data, as: UTF8.self) + "</script>"
    }
    private func event(_ title: String = "Texas State Bobcats vs Boise State Broncos") -> String {
        """
        <section id='evHead'><div class='eh-lg'><span>College Football</span></div><h1>\(title) Live Stream</h1></section>
        <a class='sl-row sl-lead' href='https://fxtrend.st\(path)/main/1'>Main 1</a>
        <a class='sl-row' href='https://ads.example\(path)/main/2'>Advertisement</a>
        """
    }
    private var player: String {
        """
        <h1>Texas State Bobcats vs Boise State Broncos</h1><div class='srs'>
        <a class='sr sr-on' href='\(path)/main/1' data-e='https://trendy48.site/embed/published-main-123'><span class='sl'>Main 1</span></a>
        <a class='sr' href='\(path)/main/2' data-e='https://trendy48.site/aura/1972'><span class='sl'>Main 2</span></a>
        <a class='sr' href='\(path)/main/3' data-e='https://ads.example/pop'><span class='sl'>Advert</span></a>
        <a class='sr' href='/event/another-game/main/1' data-e='https://trendy48.site/embed/wrong'><span class='sl'>Other game</span></a>
        </div>
        """
    }

    func testExactCollegeGameDateAndLeagueAreRequiredAndEndedGamesStayOut() throws {
        XCTAssertEqual(try FoxTrendProvider.eventPath(in: catalog(), game: game, now: now), path)
        for (key, value) in [("g", "NFL" as Any), ("t", "Texas State Bobcats vs Boise State Bengals"),
            ("e", 1), ("w", Int(now.addingTimeInterval(-19 * 3600).timeIntervalSince1970 * 1000)),
            ("w", true), ("u", "https://other.example/event/game"), ("u", "/event/../../other")] {
            var wrong = entry; wrong[key] = value
            XCTAssertNil(try FoxTrendProvider.eventPath(in: catalog(wrong), game: game, now: now))
        }
    }

    func testPublishedFeedLinksExcludeAdsOtherGamesAndEndedPages() {
        XCTAssertEqual(FoxTrendProvider.watchPages(in: event(), eventPath: path, game: game).map(\.absoluteString),
            ["https://fxtrend.st\(path)/main/1"])
        XCTAssertTrue(FoxTrendProvider.watchPages(in: event("Texas State Bobcats vs Ohio State Buckeyes"), eventPath: path, game: game).isEmpty)
        XCTAssertTrue(FoxTrendProvider.watchPages(in: event() + "<div class='sl-done'>Final</div>", eventPath: path, game: game).isEmpty)
        let sources = FoxTrendProvider.embeds(in: player, eventPath: path, game: game)
        XCTAssertEqual(sources.map(\.title), ["FoxTrend · Main 1", "FoxTrend · Main 2"])
        XCTAssertEqual(sources.map(\.url.absoluteString), ["https://trendy48.site/embed/published-main-123", "https://trendy48.site/aura/1972"])
        XCTAssertTrue(FoxTrendProvider.embeds(in: player.replacingOccurrences(of: "Boise State Broncos", with: "Boise State Bengals"), eventPath: path, game: game).isEmpty)
        XCTAssertEqual(FoxTrendProvider.embeds(in: player.replacingOccurrences(of: "href='\(path)/main/2'", with: "href='http://['"), eventPath: path, game: game).count, 1)
    }

    func testCollegeRanksKeepSchoolIdentityIncludingStateAndTech() {
        for rank in ["No. 20 ", "No 20 ", "#20 ", "(20) "] {
            XCTAssertTrue(SportsSourceIdentity.teamsMatch(rank + "Boise State Broncos vs Texas State Bobcats", game: game))
            XCTAssertTrue(SportsSourceIdentity.teamsMatch(rank + "Boise State vs Texas State", game: game))
        }
        for wrong in ["No. 20 Boise", "No. 20 Boise State Bengals", "No. 26 Boise State", "20 Boise State"] {
            XCTAssertFalse(SportsSourceIdentity.teamsMatch(wrong + " vs Texas State Bobcats", game: game))
        }
    }

    func testDiscoveryFollowsPublishedPagesAndRefreshesPlayerAddresses() async throws {
        let state = FoxTestState(responses: [FoxTrendProvider.schedule.absoluteString: try catalog(),
            "https://crackstreams.st" + path: event(), "https://fxtrend.st" + path + "/main/1": player])
        let key = UUID().uuidString
        FoxTestProtocol.register(state, key: key)
        defer { FoxTestProtocol.unregister(key) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FoxTestProtocol.self]
        config.httpAdditionalHeaders = ["X-Streamify-Fox-Test": key]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let provider = FoxTrendProvider(session: session, now: { [now] in now })
        for _ in 0..<2 { let sources = try await provider.streams(game); XCTAssertEqual(sources.count, 2) }
        // Only the schedule may stay warm. Every Watch refreshes the event/feed.
        XCTAssertEqual(state.requests.count, 5)
        XCTAssertTrue(state.requests.allSatisfy { state.responses[$0] != nil })
    }
}

private final class FoxTestState: @unchecked Sendable {
    let responses: [String: String]
    private let lock = NSLock()
    private var urls: [String] = []
    init(responses: [String: String]) { self.responses = responses }
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return urls }
    func response(_ url: String) -> String? { lock.lock(); defer { lock.unlock() }; urls.append(url); return responses[url] }
}

private final class FoxTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var states: [String: FoxTestState] = [:]
    static func register(_ state: FoxTestState, key: String) { lock.lock(); defer { lock.unlock() }; states[key] = state }
    static func unregister(_ key: String) { lock.lock(); defer { lock.unlock() }; states.removeValue(forKey: key) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let state = request.value(forHTTPHeaderField: "X-Streamify-Fox-Test").flatMap { Self.states[$0] }
        Self.lock.unlock()
        guard let url = request.url, let text = state?.response(url.absoluteString),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=UTF-8"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
