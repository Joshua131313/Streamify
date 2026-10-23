import Foundation
import XCTest
@testable import Streamify

final class DataContractTests: XCTestCase {
    func testKeychainCredentialRoundTripUsesSignedAppIdentity() throws {
        let key = "test-credential-\(UUID().uuidString)"
        defer { try? SecureCredentialStore.set("", for: key) }
        XCTAssertNil(try SecureCredentialStore.get(key))
        try SecureCredentialStore.set("fixture-token-one", for: key)
        XCTAssertEqual(try SecureCredentialStore.get(key), "fixture-token-one")
        try SecureCredentialStore.set("fixture-token-two", for: key)
        XCTAssertEqual(try SecureCredentialStore.get(key), "fixture-token-two")
        try SecureCredentialStore.set("", for: key)
        XCTAssertNil(try SecureCredentialStore.get(key))
    }

    func testMissingCredentialFailsWithActionableSetupError() async {
        do {
            _ = try await TMDBClient(token: "  \n").catalog(path: "movie/popular", kind: .movie)
            XCTFail("A missing catalog credential must not make an unauthenticated catalog request.")
        } catch CatalogError.missingToken {
            XCTAssertTrue(CatalogError.missingToken.localizedDescription.contains("Settings"))
        } catch {
            XCTFail("Expected a catalog setup error, received \(error)")
        }
    }

    func testMixedSearchDecodesMediaNamespacesAndSkipsPeople() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let result = try await TMDBClient(token: "fixture-v3-api-key", session: session)
            .catalog(path: "search/multi", page: 2, query: "Fixture & series")
        XCTAssertEqual(result.page, 2)
        XCTAssertEqual(result.totalPages, 4)
        XCTAssertEqual(result.items.map(\.key), ["movie:42", "tv:42"])
        XCTAssertEqual(result.items.map(\.title), ["Fixture movie", "Fixture series"])
        XCTAssertEqual(result.items[0].genreIDs, [12, 18])
        XCTAssertEqual(result.items[1].year, "2022")
        XCTAssertNil(result.items[1].posterURL)
    }

    func testProviderCannotPlayAniListIdentityAsTMDBTitle() {
        let provider = MediaServer(id: "fixture", label: "Fixture", movie: "https://example.com/movie/{id}",
            tv: "https://example.com/tv/{id}/{season}/{episode}")
        let anime = MediaItem(id: 42, kind: .anime, title: "Anime")
        XCTAssertNil(provider.url(media: anime, season: 1, episode: 1))
        let series = MediaItem(id: 42, kind: .tv, title: "Series")
        XCTAssertEqual(provider.url(media: series, season: -1, episode: 0)?.absoluteString, "https://example.com/tv/42/1/1")
        XCTAssertNil(secureURL("http://example.com/video"))
        XCTAssertNil(secureURL("https://user:password@example.com/video"))
        XCTAssertNil(secureURL("file:///tmp/video.mp4"))
    }

    func testAnimeSearchParserAcceptsOnlyCanonicalWatchPaths() {
        let html = """
        <a class="item poster" href="/watch/title-123">Valid relative</a>
        <a class='item' href='https://anikoto.cz/watch/second-456'>Valid absolute</a>
        <a class='item' href='/watch/title-123'>Duplicate</a>
        <a class='item' href='https://evil.example/watch/wrong-1'>Wrong host</a>
        <a class='item' href='https://anikoto.cz.evil.example/watch/wrong-2'>Suffix host</a>
        <a class='item' href='https://user@anikoto.cz/watch/wrong-3'>User info</a>
        <a class='item' href='https://anikoto.cz:8443/watch/wrong-4'>Port</a>
        <a class='item' href='http://anikoto.cz/watch/wrong-5'>Insecure</a>
        <a class='item' href='/watch/../admin'>Traversal</a>
        <a class='item' href='/watch/title-123/episode-1'>Episode link</a>
        <a class='different' href='/watch/wrong-6'>Not a search item</a>
        """
        XCTAssertEqual(AnikotoResolver.searchPaths(html), ["/watch/title-123", "/watch/second-456"])
    }

    func testAnimeSourceParserKeepsSubAndDubTokensSeparate() {
        let html = """
        <div class="type" data-type="sub"><ul>
          <li data-sv-id="323" data-link-id="sub-token">HD-1</li>
          <li data-sv-id="e54" data-link-id="other-token">Vidstream</li>
        </ul></div>
        <div class="type" data-type="dub"><ul>
          <li data-sv-id="323" data-link-id="dub-token">HD-1</li>
        </ul></div>
        """
        XCTAssertEqual(AnikotoResolver.serverToken(html, language: "sub", server: "323"), "sub-token")
        XCTAssertEqual(AnikotoResolver.serverToken(html, language: "dub", server: "323"), "dub-token")
        XCTAssertNil(AnikotoResolver.serverToken(html, language: "invalid", server: "323"))
        XCTAssertNil(AnikotoResolver.serverToken(html, language: "dub", server: "e54"))
    }

    func testBundledConfigurationPreservesAndroidCollectionsAndProviders() throws {
        let collections = FilmCollection.bundled
        let servers = MediaServer.bundled
        XCTAssertEqual(collections.count, 17, "The app must include its actual collection configuration resource.")
        XCTAssertEqual(Set(collections.map(\.id)).count, collections.count)
        XCTAssertEqual(collections.first { $0.id == 1241 }?.assetName, "collection-harry-potter")
        XCTAssertEqual(servers.count, 15)
        XCTAssertEqual(Set(servers.map(\.id)).count, servers.count)
        let movie = MediaItem(id: 42, kind: .movie, title: "Fixture")
        let series = MediaItem(id: 42, kind: .tv, title: "Fixture")
        for server in servers {
            XCTAssertNotNil(server.url(media: movie), "Invalid movie template for \(server.id)")
            XCTAssertNotNil(server.url(media: series, season: 2, episode: 3), "Invalid TV template for \(server.id)")
        }
        let optionalFields = Data("{\"id\":1,\"name\":\"Collection\",\"backdrop\":\"/images/example.jpg\"}".utf8)
        let decoded = try JSONDecoder().decode(FilmCollection.self, from: optionalFields)
        XCTAssertFalse(decoded.featured)
        XCTAssertTrue(decoded.genres.isEmpty)
    }

    @MainActor
    func testLibraryPersistsNamespacesEpisodesAndTeamPreferences() async throws {
        let suite = "streamify-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let movie = MediaItem(id: 42, kind: .movie, title: "Movie")
        let series = MediaItem(id: 42, kind: .tv, title: "Series")
        let library = LibraryStore(defaults: defaults)
        library.toggleSaved(movie); library.toggleSaved(series)
        library.record(series, season: 2, episode: 3, positionSeconds: 120, durationSeconds: 1200)
        library.record(series, season: 2, episode: 3)
        library.rememberSearch("  Andor  "); library.rememberSearch("ANDOR")
        library.toggleTeam("nba:13"); library.setGenre(18)

        let restored = LibraryStore(defaults: defaults)
        XCTAssertTrue(restored.isSaved(movie)); XCTAssertTrue(restored.isSaved(series))
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.history.first?.season, 2)
        XCTAssertEqual(restored.history.first?.episode, 3)
        XCTAssertEqual(restored.history.first?.positionSeconds, 120)
        XCTAssertEqual(restored.recentSearches, ["ANDOR"])
        XCTAssertEqual(restored.followedTeams, ["nba:13"])
        XCTAssertEqual(restored.favoriteGenres, [18])
        restored.toggleSaved(movie)
        XCTAssertFalse(restored.isSaved(movie)); XCTAssertTrue(restored.isSaved(series))
        restored.record(series, season: 2, episode: 4)
        XCTAssertEqual(restored.history.first?.positionSeconds, 0, "A different episode must not inherit the previous episode's playback time.")
    }
}

private final class CatalogFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.themoviedb.org" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.path == "/3/search/multi",
                  parts.queryItems?.first(where: { $0.name == "query" })?.value == "Fixture & series",
                  parts.queryItems?.first(where: { $0.name == "api_key" })?.value == "fixture-v3-api-key",
                  parts.queryItems?.first(where: { $0.name == "include_adult" })?.value == "false",
                  let fixture = Bundle(for: DataContractTests.self).url(forResource: "mixed-search", withExtension: "json"),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
            else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try Data(contentsOf: fixture))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
