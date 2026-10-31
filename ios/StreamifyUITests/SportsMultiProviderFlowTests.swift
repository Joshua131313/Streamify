import XCTest

/// Real selectors and retained WebKit documents, using independent local public
/// response-shaped providers. No live provider or cloud chat is queried.
final class SportsMultiProviderFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
        app.buttons["tab-sports"].tap()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("FAILURE multi-provider game sources")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE multi-provider hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
    }

    func testEveryLeagueOffersIndependentSourcesAndStartsWithTimStreams() {
        executionTimeAllowance = 360
        open("nfl")
        for league in ["nfl", "college-football", "nba", "wnba", "nhl", "mlb"] {
            if league != "nfl" {
                app.buttons["sports-player-game-picker"].tap()
                let game = app.buttons["sports-player-game-option-\(league):\(league)-fixture"]
                XCTAssertTrue(game.waitForExistence(timeout: 8))
                // Native menu rows can exist below its clipped viewport.
                // Scroll inside its upper visible portion before touching one.
                let menu = app.collectionViews.containing(.button, identifier: game.identifier).firstMatch
                for _ in 0..<4 where !game.isHittable {
                    XCTAssertTrue(menu.exists)
                    let start = menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                    let end = menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                    start.press(forDuration: 0.05, thenDragTo: end)
                }
                XCTAssertTrue(game.isHittable, "\(league)'s actual game row must be reachable.")
                capture("\(league) live game row before selection")
                // Let XCTest use the native menu row's hittable point. A custom
                // normalized point can miss UIKit's interactive region after a
                // section layout or viewport change even while isHittable is true.
                game.tap()
                let title = league == "college-football" ? "NCAAF" : league.uppercased()
                XCTAssertTrue(wait {
                    !game.exists && (self.app.buttons["sports-player-game-picker"].value as? String ?? "").hasPrefix(title + ",")
                }, "The menu must dismiss and commit \(league), preserving wrong-game detection.")
            }
            let picker = app.buttons["sports-player-source-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 12))
            XCTAssertTrue((picker.value as? String ?? "").contains("TimStreams"), "\(league) must default to TimStreams.")
            let title = league == "college-football" ? "NCAAF" : league.uppercased()
            XCTAssertTrue((app.buttons["sports-player-game-picker"].value as? String ?? "").hasPrefix(title))
            picker.tap()
            XCTAssertTrue(option("StreamFree").firstMatch.waitForExistence(timeout: 6), "\(league) needs a second independent provider.")
            XCTAssertTrue(option("DaddyLive").firstMatch.exists, "\(league) must keep its advertised channel alternatives.")
            capture("\(league) has TimStreams first and independent backup sources")
            let tim = option("TimStreams").firstMatch
            tim.tap()
            XCTAssertTrue(tim.waitForNonExistence(timeout: 5), "Source menu must finish dismissing before the next action")
        }
        app.buttons["Close player"].tap()
        XCTAssertTrue(app.buttons["sports-player-source-picker"].waitForNonExistence(timeout: 8))
    }

    func testChangingProviderKeepsTheGameAndLoadsOnlyTheSelectedPlayerDocument() {
        open("nba")
        let picker = app.buttons["sports-player-source-picker"]
        let game = app.buttons["sports-player-game-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 12))
        XCTAssertTrue(document.waitForExistence(timeout: 20))
        let matchup = game.value as? String
        var previous = document.label
        for provider in ["StreamFree", "DaddyLive", "TimStreams"] {
            picker.tap()
            let choice = option(provider).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 6))
            choice.tap()
            XCTAssertTrue(wait { (picker.value as? String ?? "").contains(provider) })
            XCTAssertTrue(wait { self.document.exists && self.document.label != previous })
            XCTAssertEqual(game.value as? String, matchup)
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).count, 1)
            previous = document.label
            capture("\(provider) loads inside the same NBA player")
        }
    }

    private var document: XCUIElement { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).firstMatch }
    private func option(_ provider: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-player-source-option-' AND label CONTAINS %@", provider))
    }
    private func open(_ league: String) {
        let rail = app.scrollViews["sports-league-rail"]
        let item = app.buttons["sports-league-option-\(league)"]
        for _ in 0..<8 where !item.isHittable {
            if item.exists && item.frame.minX < app.frame.minX { rail.swipeRight() }
            else { rail.swipeLeft() }
        }
        XCTAssertTrue(item.isHittable)
        item.tap()
        XCTAssertTrue(wait { item.isSelected })
        let watch = app.buttons["sports-watch-\(league):\(league)-fixture"]
        for _ in 0..<5 where !watch.isHittable { app.swipeUp() }
        XCTAssertTrue(watch.isHittable)
        watch.tap()
    }
    private func wait(_ test: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in test() }, object: nil)], timeout: 10) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
