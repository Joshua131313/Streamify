import XCTest

/// Profile navigation uses the real local store and catalog fixtures. No account
/// sign-in, external media download, or real credential is involved.
final class ProfileFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-profile-chooser"]
        app.launch()
        XCTAssertTrue(element("profile-chooser").waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Choose your profile"].exists)
        XCTAssertFalse(app.buttons["profile-switch-cancel"].exists, "The initial launch must ask the viewer to choose a profile.")
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE profile flow")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE profile hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    func testChooserSelectionAndSwitchingKeepActualSavedTitlesInTheirOwnProfile() {
        // This complete two-viewer flow includes three Settings visits and a
        // real catalog save. Keep its full assertions within the CI's 6m cap.
        executionTimeAllowance = 360
        capture("Profiles first launch cinematic chooser")
        choose("My profile")
        openSettings()
        let themes = app.segmentedControls.firstMatch
        XCTAssertTrue(themes.buttons["Dark"].isSelected)
        themes.buttons["Light"].tap()
        XCTAssertTrue(wait { themes.buttons["Light"].isSelected })
        app.buttons["Done"].tap()
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 6), "Existing fixture favorites belong to the original profile.")

        openSwitcher()
        XCTAssertTrue(app.buttons["profile-switch-cancel"].isHittable)
        addProfile(name: "Alex", avatar: "ocean")
        choose("Alex")
        XCTAssertEqual(app.buttons["tab-library"].value as? String, "Profile: Alex, Dragon avatar")
        openSettings()
        XCTAssertTrue(themes.buttons["Dark"].isSelected, "A new profile must not inherit another viewer’s appearance preference.")
        app.buttons["Done"].tap()
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 0"].waitForExistence(timeout: 6), "Creating a profile must not seed it with someone else's saved list.")
        XCTAssertTrue(app.buttons["History · 0"].exists)
        capture("Profiles new viewer has an empty personal library")

        app.buttons["tab-home"].tap()
        let pause = app.buttons["hero-carousel-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 12))
        if pause.label == "Pause carousel" { pause.tap() }
        app.buttons["Show Beyond the City"].tap()
        let artwork = app.buttons["Details for Beyond the City"]
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        artwork.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["download-movie:45"].waitForExistence(timeout: 8))
        let detail = app.scrollViews["media-detail-page"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.buttons["My list"].isHittable)
        detail.buttons["My list"].tap()
        XCTAssertTrue(detail.buttons["Saved"].waitForExistence(timeout: 4))
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 5))
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 1"].waitForExistence(timeout: 6))
        XCTAssertTrue(element("poster-artwork-movie:45").exists)
        capture("Profiles second viewer saves an actual catalog title")

        openSwitcher()
        choose("My profile")
        XCTAssertEqual(app.buttons["tab-library"].value as? String, "Profile: My profile, Crimson avatar")
        openSettings()
        XCTAssertTrue(themes.buttons["Light"].isSelected, "Switching back must restore this profile’s appearance.")
        app.buttons["Done"].tap()
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["History · 2"].exists)
        XCTAssertTrue(element("poster-artwork-movie:42").exists)
        XCTAssertFalse(element("poster-artwork-movie:45").exists, "Alex's saved title cannot appear in the original profile.")
        capture("Profiles original favorites and history remain intact")

        openSwitcher()
        app.buttons["profile-switch-cancel"].tap()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 5))
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
    }

    func testEditorCancelRenameAvatarsAndDeleteConfirmationPreserveTheLastProfile() {
        app.buttons["profile-manage"].tap()
        profileTile("Edit My profile").tap()
        XCTAssertTrue(app.textFields["profile-name-field"].waitForExistence(timeout: 5))
        replaceName("Unsaved name")
        app.buttons["profile-editor-cancel"].tap()
        XCTAssertTrue(profileTile("Edit My profile").waitForExistence(timeout: 5))
        XCTAssertFalse(profileTile("Edit Unsaved name").exists)

        profileTile("Edit My profile").tap()
        XCTAssertFalse(app.buttons["profile-delete"].isEnabled, "The last profile cannot be deleted.")
        app.buttons["profile-avatar-forest"].tap()
        XCTAssertTrue(app.buttons["profile-avatar-forest"].isSelected)
        replaceName("Jordan")
        capture("Profiles rename and choose an original avatar")
        saveEditor()
        XCTAssertTrue(profileTile("Edit Jordan").waitForExistence(timeout: 5))

        addProfile(name: "Guest", avatar: "gold")
        profileTile("Edit Guest").tap()
        let delete = app.buttons["profile-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        reveal(delete)
        XCTAssertTrue(delete.isEnabled)
        delete.tap()
        let confirmation = app.sheets["Delete Guest?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let confirm = confirmation.buttons["profile-delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture("Profiles deletion requires explicit confirmation")
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' AND identifier != 'profile-editor-cancel'"))
            .allElementsBoundByIndex.first { $0.isHittable }
        if let cancel { cancel.tap() }
        else {
            let dismiss = element("PopoverDismissRegion")
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            dismiss.tap()
        }
        XCTAssertTrue(wait { !confirm.exists })
        app.buttons["profile-editor-cancel"].tap()
        XCTAssertTrue(profileTile("Edit Guest").waitForExistence(timeout: 5), "Cancelling deletion must preserve Guest.")

        profileTile("Edit Guest").tap()
        reveal(app.buttons["profile-delete"])
        app.buttons["profile-delete"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(wait { !self.profileTile("Edit Guest").exists && self.profileTile("Edit Jordan").exists })
        XCTAssertEqual(profileTiles.count, 1)
        profileTile("Edit Jordan").tap()
        XCTAssertTrue(app.buttons["profile-delete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile-delete"].isEnabled)
        capture("Profiles last remaining viewer is protected from deletion")
        app.buttons["profile-editor-cancel"].tap()
        app.buttons["profile-manage"].tap()
        choose("Jordan")
    }

    func testChooserAndEditorRemainReachableInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(app.staticTexts["Choose your profile"].exists)
        reveal(app.buttons["profile-manage"])
        capture("Profiles cinematic chooser in landscape")
        app.buttons["profile-manage"].tap()
        let tile = profileTile("Edit My profile")
        reveal(tile)
        tile.tap()
        XCTAssertTrue(app.textFields["profile-name-field"].waitForExistence(timeout: 5))
        reveal(app.buttons["profile-avatar-violet"])
        app.buttons["profile-avatar-violet"].tap()
        XCTAssertTrue(app.buttons["profile-avatar-violet"].isSelected)
        reveal(app.buttons["profile-save"])
        XCTAssertTrue(app.buttons["profile-save"].isHittable)
        capture("Profiles landscape editor keeps avatars and save reachable")
        app.buttons["profile-save"].tap()
        XCTAssertTrue(profileTile("Edit My profile").waitForExistence(timeout: 5))
        reveal(app.buttons["profile-manage"])
        app.buttons["profile-manage"].tap()
        reveal(profileTile("My profile"))
        choose("My profile")
    }

    private var profileTiles: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'profile-tile-'"))
    }
    private func profileTile(_ name: String) -> XCUIElement { profileTiles.matching(NSPredicate(format: "label == %@", name)).firstMatch }
    private func choose(_ name: String) {
        let tile = profileTile(name)
        XCTAssertTrue(tile.waitForExistence(timeout: 6))
        reveal(tile)
        tile.tap()
        // Query each transition endpoint with XCTest's element waits. Wrapping
        // the disappearing chooser query in another predicate can exhaust its
        // deadline while XCTest retries an already-absent accessibility node.
        XCTAssertTrue(element("profile-chooser").waitForNonExistence(timeout: 10),
            "The chooser must disappear after selecting a profile.")
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 10),
            "The selected viewer's root controls must exist.")
        XCTAssertTrue(app.buttons["tab-home"].wait(for: \.isHittable, toEqual: true, timeout: 10),
            "The selected viewer's app must become interactive.")
    }
    private func openSwitcher() {
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Switch profiles"].waitForExistence(timeout: 4))
        app.buttons["Switch profiles"].tap()
        XCTAssertTrue(app.buttons["tab-home"].waitForNonExistence(timeout: 10),
            "Switching profiles must remove the previous viewer's root controls.")
        XCTAssertTrue(element("profile-chooser").waitForExistence(timeout: 10),
            "Switching profiles must present the chooser.")
    }
    private func openSettings() {
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 4))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
    private func addProfile(name: String, avatar: String) {
        reveal(app.buttons["profile-add"])
        app.buttons["profile-add"].tap()
        XCTAssertTrue(app.textFields["profile-name-field"].waitForExistence(timeout: 5))
        let choice = app.buttons["profile-avatar-\(avatar)"]
        reveal(choice)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        replaceName(name)
        capture("Profiles add \(name) with selected avatar")
        saveEditor()
    }
    private func replaceName(_ name: String) {
        let field = app.textFields["profile-name-field"]
        reveal(field)
        field.tap()
        let tutorial = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Speed up your typing'" )).firstMatch
        if tutorial.waitForExistence(timeout: 1) { app.buttons["Continue"].firstMatch.tap() }
        let old = field.value as? String ?? ""
        let clear = old == "Name" ? "" : String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)
        field.typeText(clear + name)
    }
    private func saveEditor() {
        let save = app.buttons["profile-save"]
        reveal(save)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(wait { !self.app.textFields["profile-name-field"].exists })
    }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<8 {
            if target.exists && target.isHittable { return }
            let editor = app.scrollViews["profile-editor-scroll"]
            let scroll = editor.exists ? editor : app.scrollViews["profile-chooser-scroll"]
            XCTAssertTrue(scroll.exists, "The active profile surface must expose its real scroll view.")
            let viewport = scroll.frame.intersection(app.frame)
            let navigationBar = app.navigationBars.firstMatch
            let chromeBottom = editor.exists && navigationBar.exists ? navigationBar.frame.maxY : viewport.minY
            let upperEdge = max(viewport.minY + 18, chromeBottom + 12)
            let keyboard = app.keyboards.firstMatch
            // Keyboard predictions sit above the XCUI Keyboard frame. Keep the
            // drag inside the visible form, away from that accessory and the
            // right scroll indicator / landscape safe-area strip.
            let lowerEdge = min(viewport.maxY - 24, keyboard.exists ? keyboard.frame.minY - 64 : viewport.maxY - 24)
            XCTAssertGreaterThan(lowerEdge - upperEdge, 30)
            let lower = upperEdge + (lowerEdge - upperEdge) * 0.86
            let upper = upperEdge + (lowerEdge - upperEdge) * 0.16
            let upward = !target.exists || target.frame.midY > (upperEdge + lowerEdge) / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX, dy: upward ? lower : upper))
            let end = origin.withOffset(CGVector(dx: viewport.midX, dy: upward ? upper : lower))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable, "The profile control must remain reachable by scrolling.")
    }
    private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: identifier).firstMatch }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
