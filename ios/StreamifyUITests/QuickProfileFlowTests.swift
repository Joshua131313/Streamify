import XCTest

/// Two real local profile stores; no account, network sign-in, or cloud write.
final class QuickProfileFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-profile-quick-switch"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
        pauseCarousel()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("FAILURE quick profile picker")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE quick profile hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
    }

    func testMyListTapAndAnchoredHoldCancelThenSwitchKeepViewerDataAndAvatar() {
        executionTimeAllowance = 360
        let library = app.buttons["tab-library"]
        library.tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(library.isSelected, "A short tap must still navigate immediately to My list.")
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.buttons["tab-search"].isSelected)
        let anchor = library.frame
        library.press(forDuration: 1)
        let picker = element("quick-profile-picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        assertFullChooserInactive()
        XCTAssertLessThanOrEqual(picker.frame.maxY, anchor.minY + 4, "The profile choices must appear directly above My list.")
        XCTAssertLessThan(picker.frame.height, app.frame.height * 0.6, "The picker must remain compact, not adapt to a sheet.")
        XCTAssertEqual(quickProfile("My profile").value as? String, "Current profile")
        XCTAssertTrue(quickProfile("My profile").isSelected)
        capture("Quick profiles anchored above My list in light mode")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.18)).tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-search"].isSelected, "Cancelling a hold must not activate the My list tap.")
        XCTAssertEqual(library.value as? String, "Profile: My profile, Crimson avatar")

        library.press(forDuration: 1)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        quickProfile("My profile").tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-search"].isSelected, "Choosing the current viewer only dismisses the picker.")

        library.press(forDuration: 1)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        quickProfile("Alex").tap()
        assertRoot(profile: "Alex", avatar: "Dragon")
        library.tap()
        XCTAssertTrue(app.buttons["Saved · 0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["History · 0"].exists)
        assertAppearance("Dark")
        capture("Quick switch opens Alex with an empty personal library")

        library.press(forDuration: 1)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(quickProfile("Alex").isSelected)
        capture("Quick profiles selected Dragon in dark mode")
        quickProfile("My profile").tap()
        assertRoot(profile: "My profile", avatar: "Crimson")
        library.tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["History · 2"].exists)
        assertAppearance("Light")
        capture("Quick switch restores original viewer library and light theme")
    }

    func testFullChooserCancelAndSelectionHandoffKeepOnlyActiveSurfaceInteractive() {
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        openFullChooser()
        capture("Full profile handoff shows only cinematic chooser")
        app.buttons["profile-manage"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Edit My profile'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["profile-switch-cancel"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        assertFullChooserInactive()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected, "Cancelling returns to the original tab and viewer.")

        openFullChooser()
        XCTAssertTrue(app.staticTexts["Choose your profile"].exists, "Reopening the chooser resets its previous edit mode after dismissal.")
        let alex = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'profile-tile-' AND label == 'Alex'")).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 5))
        alex.tap()
        assertRoot(profile: "Alex", avatar: "Dragon")
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 0"].waitForExistence(timeout: 5))
        capture("Full chooser handoff reveals selected viewer without outgoing controls")
    }

    func testManageProfilesFromHeldLibraryOpensEditingAndCancelRestoresTab() {
        app.buttons["tab-sports"].tap()
        app.buttons["tab-library"].press(forDuration: 1)
        let picker = element("quick-profile-picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let manage = app.buttons["quick-profile-manage"]
        XCTAssertTrue(manage.isHittable)
        capture("Quick profile picker includes Manage profiles")
        manage.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        let editProfile = app.buttons.matching(NSPredicate(format: "label == 'Edit My profile'")).firstMatch
        XCTAssertTrue(editProfile.waitForExistence(timeout: 8))
        XCTAssertTrue(editProfile.isHittable)
        capture("Manage profiles opens the cinematic chooser in edit mode")
        app.buttons["profile-switch-cancel"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        openFullChooser()
        XCTAssertTrue(app.staticTexts["Choose your profile"].waitForExistence(timeout: 5))
    }

    private func openFullChooser() {
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Switch profiles"].waitForExistence(timeout: 5))
        app.buttons["Switch profiles"].tap()
        XCTAssertTrue(element("profile-chooser").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-manage"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        for tab in ["home", "sports", "search", "library"] {
            XCTAssertFalse(app.buttons["tab-\(tab)"].isHittable, "The retained root must not accept input under the full chooser.")
        }
        XCTAssertFalse(element("quick-profile-picker").exists)
    }

    private func assertRoot(profile: String, avatar: String) {
        XCTAssertTrue(element("quick-profile-picker").waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-home"].wait(for: \.isHittable, toEqual: true, timeout: 8))
        assertFullChooserInactive()
        XCTAssertEqual(app.buttons["tab-library"].value as? String, "Profile: \(profile), \(avatar) avatar")
        pauseCarousel()
    }

    private func pauseCarousel() {
        let pause = app.buttons["hero-carousel-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        if pause.label == "Pause carousel" { pause.tap() }
    }

    private func assertFullChooserInactive() {
        // The gate retains the cinematic surface for its next crossfade. Its
        // container may remain in XCTest's tree, but none of its actions may
        // receive a tap while the app or the compact picker is active.
        let actions = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH 'profile-tile-' OR identifier IN {'profile-manage', 'profile-add', 'profile-switch-cancel'}"))
            .allElementsBoundByIndex
        XCTAssertTrue(actions.allSatisfy { !$0.isHittable }, "The hidden full chooser must not expose interactive profile controls.")
    }

    private func assertAppearance(_ name: String) {
        // Open from the stationary library, with Home's carousel already paused.
        // This checks the real preference without changing it during the switch.
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        let choice = app.buttons[name]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(choice.isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }

    private func quickProfile(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quick-profile-' AND label == %@", name)).firstMatch
    }
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
