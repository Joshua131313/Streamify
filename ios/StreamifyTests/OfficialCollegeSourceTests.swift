import Foundation
import XCTest
@testable import Streamify

final class OfficialCollegeSourceTests: XCTestCase {
    private func game(_ league: SportsLeague = .ncaam, state: String = "in") -> SportsGame {
        SportsGame(eventID: "401911707", league: league, date: Date(), state: state, status: "Live",
            home: SportsTeam(id: "1", name: "Tennessee State Tigers", abbreviation: "TSU", logo: ""),
            away: SportsTeam(id: "2", name: "Murray State Racers", abbreviation: "MUR", logo: ""), venue: "", broadcasts: "", link: "")
    }
    func testCanonicalOfficialYouTubeAddressesRejectOtherHostsPathsCredentialsAndQueries() {
        XCTAssertEqual(SportsService.officialCollegeEmbed("https://www.youtube.com/embed/zVVdBffub48")?.lastPathComponent, "zVVdBffub48")
        for address in ["http://www.youtube.com/embed/zVVdBffub48", "https://www.youtube.com.evil.example/embed/zVVdBffub48",
            "https://youtube.com/embed/zVVdBffub48", "https://www.youtube.com/watch?v=zVVdBffub48",
            "https://user@www.youtube.com/embed/zVVdBffub48", "https://www.youtube.com:8443/embed/zVVdBffub48",
            "https://www.youtube.com/embed/short", "https://www.youtube.com/embed/zVVdBffub48?other=1",
            "https://www.youtube.com/embed/zVVdBffub48#other", "https://www.youtube.com/embed/%7aVVdBffub48"] {
            XCTAssertNil(SportsService.officialCollegeEmbed(address), address)
        }
    }
    func testOfficialLookupUsesExactCollegeIdentityAndSurvivesThirdPartyFailures() async throws {
        let fixture = OfficialCollegeFixture(body: [["embedUrl": "https://www.youtube.com/embed/zVVdBffub48", "label": "Official · The Field of 68"]])
        defer { fixture.session.invalidateAndCancel() }
        let streams = try await SportsService(session: fixture.session).streams(game())
        XCTAssertEqual(streams.map(\.title), ["Official · The Field of 68"])
        XCTAssertEqual(streams.first?.url.absoluteString, "https://www.youtube.com/embed/zVVdBffub48")
        let request = try XCTUnwrap(fixture.requests.first { $0.host == "streamify.watch" })
        let parts = try XCTUnwrap(URLComponents(url: request, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, "/api/official-streams")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "league" }?.value, "mens-college-basketball")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "gameId" }?.value, "401911707")
    }
    func testOfficialCandidatesAreDeduplicatedAndNeverOfferedForFinalOrOtherSports() {
        let values: [[String: Any]] = [["embedUrl": "https://www.youtube.com/embed/zVVdBffub48", "label": "Official"],
            ["embedUrl": "https://www.youtube.com/embed/zVVdBffub48"], ["embedUrl": "https://evil.example/video"]]
        XCTAssertEqual(SportsService.officialCollegeSources(values, game: game(.ncaaw)).count, 1)
        XCTAssertTrue(SportsService.officialCollegeSources(values, game: game(state: "post")).isEmpty)
        XCTAssertTrue(SportsService.officialCollegeSources(values, game: game(.nba)).isEmpty)
    }
    func testNoPublishedOfficialVideoProducesAnEmptyResultAndFinalGameMakesNoRequests() async throws {
        let fixture = OfficialCollegeFixture(body: [])
        defer { fixture.session.invalidateAndCancel() }
        let service = SportsService(session: fixture.session)
        let final = try await service.streams(game(state: "post"))
        XCTAssertTrue(final.isEmpty)
        XCTAssertTrue(fixture.requests.isEmpty)
        let live = try await service.streams(game())
        XCTAssertTrue(live.isEmpty)
    }
}

private final class OfficialCollegeFixture: @unchecked Sendable {
    let session: URLSession
    let data: Data
    private let lock = NSLock()
    private var recorded: [URL] = []
    private let id = UUID().uuidString
    var requests: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(body: [[String: Any]]) {
        data = try! JSONSerialization.data(withJSONObject: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialCollegeProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Official-College-Test": id]
        session = URLSession(configuration: configuration)
        OfficialCollegeProtocol.register(self, id: id)
    }
    deinit { OfficialCollegeProtocol.unregister(id) }
    func response(_ request: URLRequest) -> (Int, Data) {
        if let url = request.url { lock.lock(); recorded.append(url); lock.unlock() }
        return request.url?.host == "streamify.watch" ? (200, data) : (503, Data("{}".utf8))
    }
}
private final class OfficialCollegeProtocol: URLProtocol {
    private final class WeakFixture {
        weak var value: OfficialCollegeFixture?
        init(_ value: OfficialCollegeFixture) { self.value = value }
    }
    private static let lock = NSLock()
    private static var fixtures: [String: WeakFixture] = [:]
    static func register(_ fixture: OfficialCollegeFixture, id: String) { lock.lock(); fixtures[id] = WeakFixture(fixture); lock.unlock() }
    static func unregister(_ id: String) { lock.lock(); fixtures.removeValue(forKey: id); lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = request.value(forHTTPHeaderField: "X-Official-College-Test").flatMap { Self.fixtures[$0]?.value }; Self.lock.unlock()
        guard let fixture, let url = request.url, let response = HTTPURLResponse(url: url, statusCode: fixture.response(request).0,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: url.host == "streamify.watch" ? fixture.data : Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
