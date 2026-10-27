import XCTest

/// Real touch gestures over the production bar and local two-profile stores.
/// No cloud account, backend message, live stream or external download is used.
final class LiquidGlassNavigationFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-profile-quick-switch"]
        app.launch()
        XCTAssertTrue(tab("home").waitForExistence(timeout: 15))
        XCTAssertTrue(element("floating-navigation").exists)
        pauseCarousel()
        assertOnlySelectedTab("home")
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE Liquid Glass navigation")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE Liquid Glass navigation hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    func testRealThumbScrubCommitsReleasedTabAndTapsRemainIndependent() {
        let home = tab("home"), search = tab("search")
        XCTAssertTrue(home.isHittable && search.isHittable)
        let originalProfile = tab("library").value as? String
        capture("Liquid Glass original Home selection")

        // XCTest's public touch API executes the whole contact synchronously.
        // Its deliberate held phase records the lens/icon/label preview for
        // visual review; assertions below inspect real committed controls.
        heldDrag(from: center(home), to: center(search),
                 activity: "Thumb crosses Sports and holds the Search preview before release")
        assertOnlySelectedTab("search")
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
        XCTAssertEqual(tab("library").value as? String, originalProfile)
        XCTAssertFalse(element("quick-profile-picker").exists)
        capture("Liquid Glass scrub released on Search")

        // Starting on a nonselected slot must select the release target,
        // rather than also firing the button beneath the initial touch.
        heldDrag(from: center(tab("sports")), to: center(tab("home")),
                 activity: "Thumb starts over Sports but releases on Home")
        assertOnlySelectedTab("home")
        XCTAssertTrue(app.buttons["hero-carousel-pause"].waitForExistence(timeout: 5))
        pauseCarousel()

        tab("sports").tap()
        assertOnlySelectedTab("sports")
        tab("home").tap()
        assertOnlySelectedTab("home")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Glass navigation must not reveal a second system tab bar.")
        capture("Liquid Glass taps keep a single independent tab selection")
    }

    func testScrubReleasedOutsideTheBarCancelsWithoutNavigatingOrOpeningProfiles() {
        let bar = element("floating-navigation")
        let originFrame = bar.frame
        let outside = screenPoint(x: tab("library").frame.midX, y: originFrame.minY - 80)
        let initialProfile = tab("library").value as? String

        // The diagonal crosses the other slots before leaving the bar. If
        // hovering committed pages, cancellation would leave a different tab.
        heldDrag(from: center(tab("home")), to: outside,
                 activity: "Thumb previews intervening tabs then releases above the bar")
        assertOnlySelectedTab("home")
        XCTAssertEqual(tab("library").value as? String, initialProfile)
        XCTAssertFalse(element("quick-profile-picker").exists)
        XCTAssertEqual(bar.frame.minY, originFrame.minY, accuracy: 1,
                       "Cancelling a thumb drag must not lift the bar or reserve a footer.")
        capture("Liquid Glass cancelled scrub restores Home")

        tab("search").tap()
        assertOnlySelectedTab("search")
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
        capture("A normal tap still works after a cancelled thumb scrub")
    }

    func testAnchoredProfileRowDragOutsideCancelsWithoutSwitchingViewerOrTab() {
        tab("search").tap()
        assertOnlySelectedTab("search")
        let picker = openQuickProfiles()
        let current = profile("My profile"), alex = profile("Alex")
        XCTAssertEqual(current.value as? String, "Current profile")
        XCTAssertTrue(current.isSelected)
        XCTAssertFalse(alex.isSelected)
        capture("Profiles remain anchored before row tracking")

        // This passes over Alex and finishes below every choice, exercising
        // the real row highlight and then its release-outside cancellation.
        let outsideY = min(app.frame.maxY - 20, picker.frame.maxY + 24)
        heldDrag(from: center(current), to: screenPoint(x: alex.frame.midX, y: outsideY),
                 activity: "Profile thumb passes over Alex then leaves all selectable rows")
        if picker.exists {
            XCTAssertTrue(profile("My profile").isSelected)
            XCTAssertFalse(profile("Alex").isSelected, "A row highlight must not change the current-profile checkmark.")
            dismissQuickProfiles()
        }
        XCTAssertEqual(tab("library").value as? String, "Profile: My profile, Crimson avatar")
        assertOnlySelectedTab("search")
        XCTAssertFalse(element("profile-chooser").isHittable,
                       "The compact row gesture must not open the full profile chooser.")
        tab("library").tap()
        assertOnlySelectedTab("library")
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["History · 2"].exists,
                      "A cancelled row drag must retain the original viewer's real library.")
        capture("Cancelled profile tracking retains original viewer and library")
    }

    func testProfileRowDragCommitsOneViewerOnReleaseAndShortTapRestoresOriginalData() {
        tab("search").tap()
        assertOnlySelectedTab("search")
        _ = openQuickProfiles()
        let current = profile("My profile"), alex = profile("Alex")
        let alexCenter = center(alex)
        heldDrag(from: center(current), to: alexCenter,
                 activity: "Profile thumb holds Alex highlighted before releasing exactly one choice")

        XCTAssertTrue(element("quick-profile-picker").waitForNonExistence(timeout: 5))
        XCTAssertTrue(tab("home").wait(for: \.isHittable, toEqual: true, timeout: 10))
        assertOnlySelectedTab("home")
        XCTAssertEqual(tab("library").value as? String, "Profile: Alex, Dragon avatar")
        pauseCarousel()
        tab("library").tap()
        XCTAssertTrue(app.buttons["Saved · 0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["History · 0"].exists,
                      "The released profile must have its own persisted library.")
        capture("Profile drag release opens Alex once with an empty library")

        _ = openQuickProfiles()
        XCTAssertTrue(profile("Alex").isSelected)
        XCTAssertEqual(profile("Alex").value as? String, "Current profile")
        profile("My profile").tap()
        XCTAssertTrue(element("quick-profile-picker").waitForNonExistence(timeout: 5))
        XCTAssertTrue(tab("home").wait(for: \.isHittable, toEqual: true, timeout: 10))
        assertOnlySelectedTab("home")
        XCTAssertEqual(tab("library").value as? String, "Profile: My profile, Crimson avatar")
        pauseCarousel()
        tab("library").tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["History · 2"].exists)
        capture("Short profile tap restores original viewer avatar and saved data")
    }

    private func openQuickProfiles() -> XCUIElement {
        let library = tab("library")
        let anchor = library.frame
        library.press(forDuration: 0.8)
        let picker = element("quick-profile-picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(profile("My profile").waitForExistence(timeout: 5))
        XCTAssertTrue(profile("Alex").exists)
        XCTAssertLessThanOrEqual(picker.frame.maxY, anchor.minY + 4,
                                "Profile choices must stay directly above their My List anchor.")
        XCTAssertLessThan(picker.frame.height, app.frame.height * 0.6,
                          "A hold must open a compact anchored picker, not a sheet.")
        return picker
    }

    private func dismissQuickProfiles() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.18)).tap()
        XCTAssertTrue(element("quick-profile-picker").waitForNonExistence(timeout: 5))
    }

    private func heldDrag(from start: XCUICoordinate, to end: XCUICoordinate, activity: String) {
        XCTContext.runActivity(named: activity) { _ in
            start.press(forDuration: 0.08, thenDragTo: end,
                        withVelocity: XCUIGestureVelocity(rawValue: 130), thenHoldForDuration: 0.65)
        }
    }

    private func center(_ target: XCUIElement) -> XCUICoordinate {
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    private func screenPoint(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x - app.frame.minX, dy: y - app.frame.minY))
    }

    private func assertOnlySelectedTab(_ selected: String, file: StaticString = #filePath, line: UInt = #line) {
        for name in ["home", "sports", "search", "library"] {
            XCTAssertEqual(tab(name).isSelected, name == selected,
                           "Only \(selected) may be committed; \(name) has the wrong selected trait.", file: file, line: line)
        }
    }

    private func pauseCarousel() {
        let pause = app.buttons["hero-carousel-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        if pause.label == "Pause carousel" { pause.tap() }
    }

    private func tab(_ name: String) -> XCUIElement { app.buttons["tab-\(name)"] }
    private func profile(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quick-profile-' AND label == %@", name)).firstMatch
    }
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
