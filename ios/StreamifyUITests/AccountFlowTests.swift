import XCTest

/// Exercises the real account form with local validation only. Fixture launches
/// leave Firebase unconfigured; no credentials are sent to an auth service.
final class AccountFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE account form")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE account form hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
    }

    func testRegistrationValidationClearsPasswordAndPreservesGuestProfile() {
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        let guestProfile = app.buttons["tab-library"].value as? String
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()

        let mode = app.buttons["account-mode"]
        reveal(mode)
        XCTAssertEqual(mode.label, "Create account")
        mode.tap()
        XCTAssertEqual(app.buttons["account-submit"].label, "Create account")
        XCTAssertFalse(app.buttons["account-reset-password"].exists)

        let email = app.textFields["account-email"]
        reveal(email)
        email.tap()
        email.typeText("local-review@example.invalid")
        let password = app.secureTextFields["account-password"]
        reveal(password)
        XCTAssertTrue(password.exists, "Passwords must use the native secure input.")
        password.tap()
        password.typeText("x")

        let submit = app.buttons["account-submit"]
        reveal(submit)
        submit.tap()
        let error = app.staticTexts["account-auth-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Use a password with at least 6 characters.")
        XCTAssertEqual(email.value as? String, "local-review@example.invalid")
        let clearedValue = password.value as? String ?? ""
        XCTAssertTrue(clearedValue.isEmpty || clearedValue == "Password", "Submitting must clear the entered password even when local validation fails.")
        XCTAssertFalse(app.buttons["account-sign-out"].exists)
        XCTAssertTrue(submit.isEnabled, "A validation failure must leave the form usable.")
        reveal(error)
        capture("Account registration local validation and secure input")

        reveal(mode)
        mode.tap()
        XCTAssertEqual(app.buttons["account-submit"].label, "Sign in")
        XCTAssertTrue(app.buttons["account-reset-password"].exists)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-library"].value as? String, guestProfile)
        XCTAssertTrue(app.buttons["tab-library"].isSelected)
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<15 {
            if target.exists && target.isHittable { return }
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: up ? 0.78 : 0.28))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: up ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable, "The account control must be reachable with the keyboard present.")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
