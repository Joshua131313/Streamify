import XCTest

final class TennisFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-tennis-fixture"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "FAILURE tennis flow"; screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE tennis hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
    }

    func testTennisShowsAllToursThenFiltersAndOpensSetScoring() {
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
        app.buttons["tab-sports"].tap()
        let tennis = app.buttons["sports-league-option-tennis"]
        let rail = app.scrollViews["sports-league-rail"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        for _ in 0..<6 where !tennis.isHittable { rail.swipeLeft() }
        XCTAssertTrue(tennis.isHittable); tennis.tap()
        XCTAssertTrue(app.buttons["tennis-tour-challenger"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Jannik Sinner (8)"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["sports-filter-All"].exists)
        XCTAssertFalse(app.staticTexts["Doubles Player One / Partner"].exists)
        XCTAssertTrue(app.images["Jannik Sinner serving"].exists)
        app.buttons["sports-menu"].tap()
        app.buttons["sports-filter-picker"].tap()
        let doublesToggle = app.switches["tennis-show-doubles"]
        XCTAssertTrue(doublesToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(doublesToggle.value as? String, "0")
        // The switch accessibility frame includes its noninteractive row label.
        let nativeSwitch = doublesToggle.switches.firstMatch
        let control = nativeSwitch.exists ? nativeSwitch : doublesToggle
        // Operate the real native thumb; iPadOS 26 exposes the whole List row
        // and its inner switch as separate activation targets.
        let from = control.coordinate(withNormalizedOffset: CGVector(dx: nativeSwitch.exists ? 0.25 : 0.87, dy: 0.5))
        let to = control.coordinate(withNormalizedOffset: CGVector(dx: nativeSwitch.exists ? 0.8 : 0.96, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in doublesToggle.value as? String == "1" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        app.buttons["sports-filter-done"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Doubles Player One / Partner"].waitForExistence(timeout: 5))
        app.swipeDown()
        app.buttons["tennis-tour-wta"].tap()
        app.buttons["sports-filter-Pregame"].tap()
        XCTAssertTrue(app.staticTexts["Iga Swiatek (8)"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Jannik Sinner (8)"].exists)
        app.buttons["tennis-tour-challenger"].tap()
        app.buttons["sports-filter-Final"].tap()
        XCTAssertTrue(app.staticTexts["Jasika O."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Iga Swiatek (8)"].exists)
        app.buttons["tennis-tour-atp"].tap()
        let live = app.buttons["sports-quick-live"]
        XCTAssertTrue(live.exists && live.isEnabled)
        // Xcode 26 can report no AX hit point for the visible tab after its
        // count badge is inserted. Send a real touch to the Live text, then
        // require the resulting live card; this does not invoke its action.
        XCTAssertTrue(app.frame.contains(live.frame))
        live.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let card = app.buttons["sports-game-tennis:espn-atp-185682"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let player = app.buttons["sports-card-team-tennis:espn-atp-185682-atp-1000"]
        XCTAssertTrue(player.label.contains("Set scores: 6, 3"))
        XCTAssertTrue(player.label.contains("Current game points: 15"))
        let liveCard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        liveCard.name = "Tennis Soft Spotlight live card"; liveCard.lifetime = .keepAlways; add(liveCard)
        card.tap()
        let sets = app.buttons["sports-game-tab-Sets"]
        let setOne = app.buttons["Set 1"]
        XCTAssertTrue(setOne.waitForExistence(timeout: 10)); setOne.tap()
        let firstGame = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Game 1")).firstMatch
        XCTAssertTrue(firstGame.waitForExistence(timeout: 5)); firstGame.tap()
        XCTAssertTrue(app.staticTexts["Point 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Break"].exists)
        XCTAssertTrue(sets.waitForExistence(timeout: 8)); sets.tap()
        XCTAssertTrue(app.scrollViews["sports-scoring-periods"].waitForExistence(timeout: 8) || app.otherElements["sports-scoring-periods"].exists)
        XCTAssertFalse(app.buttons["sports-game-tab-Team stats"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "Tennis set scoring"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLiveCardWatchWithoutStreamOpensField() {
        let sports = app.buttons["tab-sports"]
        XCTAssertTrue(sports.waitForExistence(timeout: 15)); sports.tap()
        let schedule = app.scrollViews["sports-screen"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        let watch = app.buttons["sports-watch-tennis:espn-atp-185682"]
        let navigation = app.descendants(matching: .any).matching(identifier: "floating-navigation").firstMatch
        let navigationTop = navigation.exists && !navigation.frame.isEmpty ? navigation.frame.minY : app.frame.maxY - 110
        guard tapWhenVisible(watch, in: schedule, below: schedule.frame.minY + 12, above: navigationTop - 12, attempts: 14) else { return }

        let gameCenter = app.navigationBars["Game center"]
        XCTAssertTrue(gameCenter.waitForExistence(timeout: 12), "Watch should open Game Center when the stream lookup is empty")
        let field = app.descendants(matching: .any).matching(identifier: "sports-center-field-tennis").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["sports-center-mode-field"].isSelected)
        XCTAssertFalse(app.alerts["Source unavailable"].exists)
        let tracker = app.webViews.firstMatch
        let pointDetails = tracker.buttons["Show point details"]
        XCTAssertTrue(pointDetails.waitForExistence(timeout: 10))
        let scroll = app.scrollViews.containing(.any, identifier: "sports-center-mode-field").firstMatch
        XCTAssertTrue(scroll.exists)
        guard tapWhenVisible(pointDetails, in: scroll, below: gameCenter.frame.maxY + 12, above: app.frame.maxY - 40, attempts: 4) else { return }
        XCTAssertTrue(tracker.staticTexts["Point details displayed"].waitForExistence(timeout: 5))
        let fieldCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fieldCapture.name = "Interactive Tennis Field after Watch with no stream"; fieldCapture.lifetime = .keepAlways; add(fieldCapture)
    }

    @discardableResult private func tapWhenVisible(_ target: XCUIElement, in scroll: XCUIElement,
                                                   below top: CGFloat, above bottom: CGFloat, attempts: Int) -> Bool {
        let screen = app.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for attempt in 0...attempts {
            let area = scroll.frame.intersection(screen)
            let minY = max(area.minY + 8, top), maxY = min(area.maxY - 8, bottom)
            guard !area.isEmpty, maxY > minY + 48 else { break }
            let frame = target.exists ? target.frame : .null
            if !frame.isEmpty, frame.midX >= area.minX + 8, frame.midX <= area.maxX - 8,
               frame.midY >= minY + 8, frame.midY <= maxY - 8 {
                origin.withOffset(CGVector(dx: frame.midX - screen.minX, dy: frame.midY - screen.minY)).tap()
                return true
            }
            guard attempt < attempts else { break }
            // Stay inside the visible content gutter to avoid the floating tab bar,
            // and avoid querying the AX hit point for a clipped SwiftUI control.
            let reverse = !frame.isEmpty && frame.midY < minY
            let x = area.maxX - screen.minX - 5
            let distance = frame.isEmpty ? (maxY - minY) * 0.58 : min(160, (maxY - minY) * 0.4)
            let startY = (minY + maxY) / 2 + (reverse ? -distance / 2 : distance / 2)
            let endY = startY + (reverse ? distance : -distance)
            let start = origin.withOffset(CGVector(dx: x, dy: startY - screen.minY))
            let end = origin.withOffset(CGVector(dx: x, dy: endY - screen.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("\(target) did not enter the unobstructed scroll viewport")
        return false
    }

    func testDoubleTapActiveHomeTabReturnsToTopWithoutChangingTab() {
        let home = app.buttons["tab-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        app.swipeUp(); app.swipeUp()
        home.doubleTap()
        XCTAssertTrue(app.staticTexts["The game is on."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
    }
}
