import Foundation
import XCTest
@testable import Streamify

@MainActor
final class BrowseRetentionTests: XCTestCase {
    func testTabReturnAndFilterRoundTripKeepLoadedPagesWithoutRequests() async throws {
        let fixture = BrowseCacheFixture()
        defer { fixture.session.invalidateAndCancel() }
        let client = TMDBClient(token: UUID().uuidString, session: fixture.session)
        let model = BrowseModel()
        await load(model, client, kind: .movie)
        await load(model, client, kind: .movie, first: false)
        let original = model.items
        XCTAssertEqual(model.page, 2)
        XCTAssertEqual(fixture.calls, 2)
        await load(model, client, kind: .movie)
        XCTAssertEqual(model.items, original)
        XCTAssertEqual(model.page, 2)
        XCTAssertEqual(fixture.calls, 2, "Returning to a visible tab must not restart page one.")
        await load(model, client, kind: .tv)
        XCTAssertEqual(model.page, 1)
        await load(model, client, kind: .movie)
        XCTAssertEqual(model.items, original)
        XCTAssertEqual(model.page, 2)
        XCTAssertEqual(fixture.calls, 3, "Switching back restores that filter's paginated results.")
    }

    func testExplicitRefreshBypassesCacheAndFailureKeepsVisibleResults() async throws {
        let fixture = BrowseCacheFixture()
        defer { fixture.session.invalidateAndCancel() }
        let client = TMDBClient(token: UUID().uuidString, session: fixture.session)
        let model = BrowseModel()
        await load(model, client, kind: .movie)
        let original = model.items
        fixture.status = 503
        await load(model, client, kind: .movie, refresh: true)
        XCTAssertEqual(fixture.calls, 2)
        XCTAssertEqual(model.items, original)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.loading)
        fixture.status = 200
        await load(model, client, kind: .movie, refresh: true)
        XCTAssertEqual(fixture.calls, 3)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.items.isEmpty)
    }

    func testSearchAndCredentialsUseSeparateSnapshots() async throws {
        let fixture = BrowseCacheFixture()
        defer { fixture.session.invalidateAndCancel() }
        let client = TMDBClient(token: UUID().uuidString, session: fixture.session)
        let model = BrowseModel()
        await load(model, client, kind: .movie, query: "dragon")
        let dragon = model.items
        await load(model, client, kind: .movie, query: "space")
        XCTAssertNotEqual(model.items, dragon)
        await load(model, client, kind: .movie, query: "dragon")
        XCTAssertEqual(model.items, dragon)
        XCTAssertEqual(fixture.calls, 2)
        let changed = TMDBClient(token: UUID().uuidString, session: fixture.session)
        await load(model, changed, kind: .movie, query: "dragon")
        XCTAssertEqual(fixture.calls, 3, "Changing the catalog account must revalidate instead of reusing the old snapshot.")
    }

    private func load(_ model: BrowseModel, _ client: TMDBClient, kind: MediaKind, query: String = "", first: Bool = true, refresh: Bool = false) async {
        await model.load(client: client, kind: kind, query: query, genre: 0, animeGenre: "", provider: 0,
                         topRated: false, first: first, forceReload: refresh)
    }
}

private final class BrowseCacheFixture: @unchecked Sendable {
    let session: URLSession
    private let lock = NSLock()
    private var requestCount = 0
    private var responseStatus = 200
    var calls: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    var status: Int {
        get { lock.lock(); defer { lock.unlock() }; return responseStatus }
        set { lock.lock(); defer { lock.unlock() }; responseStatus = newValue }
    }
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BrowseCacheProtocol.self]
        session = URLSession(configuration: configuration)
        BrowseCacheProtocol.respond = { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            self.lock.lock(); self.requestCount += 1; let status = self.responseStatus; self.lock.unlock()
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let page = Int(components?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
            let query = components?.queryItems?.first { $0.name == "query" }?.value ?? "popular"
            let data = try JSONSerialization.data(withJSONObject: ["page": page, "total_pages": 3,
                "results": [["id": page, "title": query + String(page), "name": query + String(page)]]])
            return (status, data)
        }
    }
}

private final class BrowseCacheProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
