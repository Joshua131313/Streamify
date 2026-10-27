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
        // A single bulk typing event lost characters on the cold iOS simulator.
        // Send individual key events, retaining the exact full-value assertion.
        for character in "local-review@example.invalid" { email.typeText(String(character)) }
        XCTAssertEqual(email.value as? String, "local-review@example.invalid")
        let password = app.secureTextFields["account-password"]
        // Use the form's real Next action. On iOS26 XCTest can throw while
        // asking an unfocused SecureTextField for its activation point, even
        // when the field is fully visible above the email keyboard.
        let next = app.keyboards.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(password.exists, "Passwords must use the native secure input.")
        dismissStrongPasswordSuggestion(waitForAppearance: true)
        password.typeText("x")
        dismissStrongPasswordSuggestion(waitForAppearance: true)
        XCTAssertEqual((password.value as? String ?? "").count, 1,
            "The real secure field must contain exactly the one-character validation input.")

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
            dismissStrongPasswordSuggestion(waitForAppearance: false)
            if target.exists && target.isHittable { return }
            let bounds = app.frame
            let top = bounds.minY + bounds.height * 0.2
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists
                ? min(bounds.maxY - 24, keyboard.frame.minY - 20)
                : bounds.minY + bounds.height * 0.85
            XCTAssertGreaterThan(bottom - top, 44, "The account sheet must leave a scrollable viewport above the keyboard.")
            guard bottom - top > 44 else { return }
            // Start inside the visible scroll content, never on the keyboard.
            // The previous 78%-of-screen start was below the keyboard's top.
            let low = bottom - 20
            let high = top + 20
            let up = !(target.exists && target.frame.maxY < (top + bottom) / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: bounds.width * 0.95, dy: (up ? low : high) - bounds.minY))
            let end = origin.withOffset(CGVector(dx: bounds.width * 0.95, dy: (up ? high : low) - bounds.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable, "The account control must be reachable with the keyboard present.")
    }

    private func dismissStrongPasswordSuggestion(waitForAppearance: Bool) {
        let suggestion = app.staticTexts["Use Strong Password?"]
        guard waitForAppearance ? suggestion.waitForExistence(timeout: 0.8) : suggestion.exists else { return }
        // iOS26's real password suggestion sheet overlays the form. Decline
        // generation using its own Close control; keep .newPassword production
        // semantics and the test's actual one-character secure entry intact.
        let close = app.buttons.matching(NSPredicate(format: "identifier == 'xmark' AND label == 'Close'"))
            .allElementsBoundByIndex.first { $0.isHittable && $0.frame.maxY < suggestion.frame.minY }
        XCTAssertNotNil(close, "The visible native password suggestion must provide its own dismissal.")
        close?.tap()
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5), "The native suggestion must close before scrolling the account form.")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
