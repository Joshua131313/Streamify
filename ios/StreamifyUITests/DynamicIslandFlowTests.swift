import XCTest

final class DynamicIslandFlowTests: XCTestCase {
    func testExpandedIslandKeepsTeamNamesGameStatusAndWatch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures", "--ui-island-review"]
        app.launch(); defer { app.activate(); app.terminate() }
        let status = app.staticTexts["live-activity-review-state"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertTrue(wait { status.label != "Preparing Live Activity" })
        try XCTSkipIf(status.label.contains("unavailable"), status.label)
        XCTAssertEqual(status.label, "Live Activity ready")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The native expanded presentation is owned by SpringBoard, not the app.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
        let watch = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Watch")).firstMatch
        XCTAssertTrue(watch.waitForExistence(timeout: 10))
        XCTAssertTrue(springboard.staticTexts["Thunder"].exists)
        XCTAssertTrue(springboard.staticTexts["Mavericks"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Expanded Dynamic Island fuller tracked-game scoreboard"; shot.lifetime = .keepAlways; add(shot)
        app.activate()
        XCTAssertTrue(wait { status.label == "Live Activity ended" })
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10) == .completed
    }
}
