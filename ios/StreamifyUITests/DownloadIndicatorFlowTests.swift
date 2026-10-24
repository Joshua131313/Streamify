import XCTest

/// Deterministic transfer states only; these fixtures never start a network
/// download. The production buttons still perform their normal navigation/cancel.
final class DownloadIndicatorFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let knownID = "00000000-0000-0000-0000-000000000143"
    private let unknownID = "00000000-0000-0000-0000-000000000144"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-download-status-fixture"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE download indicators")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE download indicator hierarchy"
            hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testRealFractionsUnknownTotalsAndCancellationUpdateHeader() {
        let toolbar = app.buttons["open-downloads"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        XCTAssertTrue(wait { self.value(toolbar) == "2 downloads in progress, total size unknown" },
            "A transfer with an unknown total must keep the aggregate indeterminate.")
        capture("Download activity header with an unknown aggregate")

        // Open the actual movie hero. Its active download action must keep its
        // navigation behavior rather than silently becoming a stop button.
        let firstSlide = app.buttons["Show The Last Horizon"].firstMatch
        XCTAssertTrue(firstSlide.waitForExistence(timeout: 10))
        let carouselPause = app.buttons["hero-carousel-pause"]
        if carouselPause.label == "Pause carousel" { carouselPause.tap() }
        firstSlide.tap()
        let details = app.buttons["Details for The Last Horizon"].firstMatch
        XCTAssertTrue(wait { details.exists && details.isHittable })
        details.tap()
        let movieDownload = app.buttons["download-movie:42"]
        XCTAssertTrue(movieDownload.waitForExistence(timeout: 8))
        reveal(movieDownload)
        XCTAssertEqual(value(movieDownload), "25 percent")
        XCTAssertTrue(movieDownload.label.contains("Downloading"))
        capture("Movie download action displays the actual 25 percent ring")
        movieDownload.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5),
            "Tapping the movie's progress ring must still open Downloads.")

        let known = app.buttons["download-activity-\(knownID)"]
        let unknown = app.buttons["download-activity-\(unknownID)"]
        XCTAssertTrue(known.waitForExistence(timeout: 5))
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        XCTAssertEqual(value(known), "25 percent")
        XCTAssertEqual(value(unknown), "Downloading. Total size unknown")
        XCTAssertFalse(value(unknown).contains("percent"), "Unknown totals must never display invented percentages.")
        XCTAssertTrue(known.label.contains("Cancel download"))
        XCTAssertGreaterThanOrEqual(known.frame.width, 44)
        XCTAssertGreaterThanOrEqual(known.frame.height, 44)
        capture("Downloads uses matching determinate and indeterminate rings")

        unknown.tap()
        XCTAssertTrue(wait { !unknown.exists }, "The ring's stop control must cancel its own transfer.")
        XCTAssertTrue(known.exists, "Canceling another episode must preserve the movie's active transfer.")
        XCTAssertEqual(value(known), "25 percent")
        app.navigationBars["Downloads"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 5))
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(wait { toolbar.isHittable && self.value(toolbar) == "1 download in progress, 25 percent" },
            "With only the known transfer left, the header must expose its real byte fraction.")
        capture("Download activity header reflects the remaining known transfer")

        toolbar.tap()
        XCTAssertTrue(known.waitForExistence(timeout: 5))
        known.tap()
        XCTAssertTrue(wait { !known.exists })
        XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].exists,
            "Canceling active transfers must preserve the completed offline video.")
        app.navigationBars["Downloads"].buttons["Close"].tap()
        XCTAssertTrue(wait { toolbar.isHittable && self.value(toolbar) == "No active downloads" })
        capture("Download activity clears after the last transfer is canceled")
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<10 {
            if target.exists && target.isHittable { return }
            // Scroll the content gutter, away from media buttons and the detail
            // card's downward-dismiss gesture, until this action is visible.
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.75 : 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.35 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
