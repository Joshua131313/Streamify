import Foundation
import XCTest
@testable import Streamify

final class CollectionCatalogTests: XCTestCase {
    func testMiddleEarthManifestPreservesCollectionAndAddsMixedCatalogIdentities() throws {
        let collections = FilmCollection.bundled
        XCTAssertEqual(collections.count, 17)
        let middleEarth = try XCTUnwrap(collections.first { $0.id == 119 })
        XCTAssertEqual(middleEarth.assetName, "collection-lord-of-the-rings")
        XCTAssertEqual(Set(middleEarth.includes.map(\.key)), ["movie:1362", "movie:123", "movie:1361",
            "movie:49051", "movie:57158", "movie:122917", "tv:84773", "movie:839033"])
        XCTAssertEqual(middleEarth.includes.count, 8)
        XCTAssertTrue(collections.filter { $0.id != 119 }.allSatisfy { $0.includes.isEmpty })
    }

    func testCollectionLoadsMoviesAndSeriesInReleaseOrderWithoutDuplicateParts() async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let details = try await TMDBClient(token: "complete-fixture", session: session).collection(id: 119)
        XCTAssertEqual(details.movies.map(\.key), ["movie:1362", "movie:123", "movie:1361", "movie:120", "movie:121",
            "movie:122", "movie:49051", "movie:57158", "movie:122917", "tv:84773", "movie:839033"])
        XCTAssertEqual(details.unavailableCount, 0)
        XCTAssertEqual(details.mediaSummary, "10 movies · 1 series")
        let series = try XCTUnwrap(details.movies.first { $0.id == 84773 })
        XCTAssertEqual(series.kind, .tv, "The show must open TV details and episode playback, never movie details.")
        XCTAssertEqual(series.posterPath, "/fixture-84773.jpg")
    }

    func testOneUnavailableExtraKeepsAllOtherTitlesAndExposesRetryState() async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let details = try await TMDBClient(token: "partial-fixture", session: session).collection(id: 119)
        XCTAssertEqual(details.unavailableCount, 1)
        XCTAssertEqual(details.movies.count, 10)
        XCTAssertTrue(details.movies.contains { $0.key == "movie:120" })
        XCTAssertTrue(details.movies.contains { $0.key == "tv:84773" })
        XCTAssertFalse(details.movies.contains { $0.key == "movie:839033" })
    }

    func testMergeDeduplicatesByKindAndIdentityAndPreservesBaseMetadata() {
        let original = MediaItem(id: 7, kind: .movie, title: "Original", releaseDate: "2000-01-01")
        let duplicate = MediaItem(id: 7, kind: .movie, title: "Duplicate", releaseDate: "2001-01-01")
        let series = MediaItem(id: 7, kind: .tv, title: "Series", releaseDate: "2000-01-01")
        let undated = MediaItem(id: 8, kind: .movie, title: "Undated")
        let details = CollectionDetails.merging(overview: "", base: [original, original], additional: [undated, series, duplicate])
        XCTAssertEqual(details.movies.map(\.key), ["movie:7", "tv:7", "movie:8"])
        XCTAssertEqual(details.movies.first?.title, "Original")
    }

    private func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiddleEarthFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MiddleEarthFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.themoviedb.org" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let dates = [1362: "1977-11-27", 123: "1978-11-15", 1361: "1980-05-11", 120: "2001-12-19",
                121: "2002-12-18", 122: "2003-12-17", 49051: "2012-12-12", 57158: "2013-12-11",
                122917: "2014-12-10", 84773: "2022-09-01", 839033: "2024-12-11"]
            func media(_ id: Int, tv: Bool = false) -> [String: Any] {
                ["id": id, tv ? "name" : "title": "Fixture \(id)", tv ? "first_air_date" : "release_date": dates[id] ?? "",
                 "poster_path": "/fixture-\(id).jpg"]
            }
            let json: [String: Any]
            let status: Int
            if url.path == "/3/collection/119" {
                json = ["overview": "Collection fixture", "parts": [media(120), media(121), media(122), media(120)]]
                status = 200
            } else {
                let components = url.path.split(separator: "/")
                guard components.count == 3, let id = Int(components[2]), dates[id] != nil,
                      components[1] == (id == 84773 ? "tv" : "movie") else { throw URLError(.badServerResponse) }
                json = media(id, tv: id == 84773)
                let partial = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .contains { $0.name == "api_key" && $0.value == "partial-fixture" } == true
                status = partial && id == 839033 ? 503 : 200
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
