import Foundation
import UIKit
import XCTest
@testable import Streamify

final class AppQuickActionTests: XCTestCase {
    func testStaticHomeScreenActionsAndWidgetSchemeAreRegistered() throws {
        let items = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        XCTAssertEqual(items.compactMap { $0["UIApplicationShortcutItemType"] as? String }, AppQuickAction.allCases.map(\.rawValue))
        XCTAssertEqual(items.compactMap { $0["UIApplicationShortcutItemTitle"] as? String }, ["My Downloads", "My Favorites", "Sports"])
        for item in items {
            let symbol = try XCTUnwrap(item["UIApplicationShortcutItemIconSymbolName"] as? String)
            XCTAssertNotNil(UIImage(systemName: symbol))
        }
        let urlTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        XCTAssertTrue(urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.contains("streamify"))
    }

    @MainActor func testColdRequestWaitsForRootAndIsConsumedOnceWhileWarmRepeatsHaveNewIdentity() throws {
        let router = AppQuickActionRouter()
        XCTAssertTrue(router.enqueue(shortcutType: AppQuickAction.downloads.rawValue))
        let cold = try XCTUnwrap(router.pending)
        XCTAssertEqual(cold.destination, .downloads)
        XCTAssertFalse(router.enqueue(shortcutType: "other.app.downloads"))
        XCTAssertEqual(router.pending, cold, "Unrecognized actions cannot discard a queued launch request.")
        XCTAssertEqual(router.takePending(), cold)
        XCTAssertNil(router.takePending(), "A foreground round trip must not replay a consumed action.")
        XCTAssertTrue(router.enqueue(shortcutType: AppQuickAction.downloads.rawValue))
        let warm = try XCTUnwrap(router.takePending())
        XCTAssertEqual(warm.destination, .downloads)
        XCTAssertNotEqual(warm.id, cold.id, "A second deliberate press of the same shortcut remains actionable.")
        XCTAssertNil(router.pending)
    }

    @MainActor func testWidgetRoutesAcceptOnlyKnownSportsAndBoundedNumericESPNIdentities() throws {
        let router = AppQuickActionRouter()
        XCTAssertTrue(router.enqueue(url: try XCTUnwrap(URL(string: "streamify://sports"))))
        XCTAssertEqual(router.takePending()?.destination, .sports)
        for league in SportsLeague.allCases {
            XCTAssertTrue(router.enqueue(url: try XCTUnwrap(URL(string: "streamify://sports/watch?league=\(league.rawValue)&event=401020304"))))
            XCTAssertEqual(router.takePending()?.destination, .watchSports(league: league, eventID: "401020304"))
        }
        for value in [
            "https://sports/watch?league=nba&event=1", "streamify://other/watch?league=nba&event=1",
            "streamify://sports/unknown", "streamify://sports?league=nba",
            "streamify://sports/watch?league=unknown&event=1", "streamify://sports/watch?league=nba",
            "streamify://sports/watch?league=nba&event=", "streamify://sports/watch?league=nba&event=../1",
            "streamify://sports/watch?league=nba&event=١٢", "streamify://sports/watch?league=nba&event=\(String(repeating: "1", count: 33))",
            "streamify://sports/watch?league=nba&event=1&event=2", "streamify://sports/watch?league=nba&event=1&url=https://example.com",
            "streamify://user@sports/watch?league=nba&event=1", "streamify://sports:99/watch?league=nba&event=1",
            "streamify://sports/watch?league=nba&event=1#player"
        ] {
            XCTAssertFalse(router.enqueue(url: try XCTUnwrap(URL(string: value))), value)
            XCTAssertNil(router.pending)
        }
    }

    @MainActor func testRoutingKeepsGuestFavoritesHistoryProgressAndPreferences() throws {
        let name = "streamify-quick-actions-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let library = LibraryStore(defaults: defaults)
        let media = MediaItem(id: 42, kind: .movie, title: "Saved fixture")
        library.toggleSaved(media)
        library.record(media, positionSeconds: 49, durationSeconds: 100)
        library.rememberSearch("Fixture")
        library.toggleTeam("nba:200")
        let before = defaults.data(forKey: "streamify.ios.guestLibrary.v1")
        let router = AppQuickActionRouter()
        for action in AppQuickAction.allCases {
            XCTAssertTrue(router.enqueue(shortcutType: action.rawValue))
            XCTAssertEqual(router.takePending()?.destination, action.destination)
        }
        XCTAssertEqual(defaults.data(forKey: "streamify.ios.guestLibrary.v1"), before)
        let reloaded = LibraryStore(defaults: defaults)
        XCTAssertEqual(reloaded.saved.map(\.key), [media.key])
        XCTAssertEqual(reloaded.history.first?.positionSeconds, 49)
        XCTAssertEqual(reloaded.recentSearches, ["Fixture"])
        XCTAssertEqual(reloaded.followedTeams, ["nba:200"])
    }

    func testWidgetWatchFetchesFreshESPNHeaderAndRejectsMismatchedIdentity() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuickActionSummaryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = SportsService(session: session)
        let game = try await service.game(league: .nba, eventID: "401020304")
        XCTAssertEqual(game.eventID, "401020304")
        XCTAssertEqual(game.home.abbreviation, "TOR")
        XCTAssertTrue(game.isLive)
        do {
            _ = try await service.game(league: .nba, eventID: "401020305")
            XCTFail("An ESPN response for another event must not launch the wrong game.")
        } catch SportsServiceError.invalidResponse { }
        do {
            _ = try await service.game(league: .nba, eventID: "../summary")
            XCTFail("An invalid event identity must be rejected before creating a request.")
        } catch SportsServiceError.invalidURL { }
    }
}

private final class QuickActionSummaryProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "site.api.espn.com",
              url.path == "/apis/site/v2/sports/basketball/nba/summary",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "event" })?.value != nil,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let header: [String: Any] = ["id": "401020304", "date": "2026-10-24T03:30:00Z", "competitions": [[
            "status": ["type": ["state": "in", "shortDetail": "4th"]],
            "competitors": [
                ["homeAway": "home", "score": "99", "team": ["id": "200", "displayName": "Toronto", "abbreviation": "TOR"]],
                ["homeAway": "away", "score": "98", "team": ["id": "100", "displayName": "Boston", "abbreviation": "BOS"]]
            ]
        ]]]
        guard let data = try? JSONSerialization.data(withJSONObject: ["header": header]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
