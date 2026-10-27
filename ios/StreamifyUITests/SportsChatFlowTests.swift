import XCTest

/// Every launch uses local fixtures. These tests never configure Firebase,
/// create anonymous accounts, or publish messages to a real chat room.
final class SportsChatFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        if name.contains("testChatConnectionTimeout") { app.launchArguments.append("--ui-chat-stalled-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("FAILURE local guest chat")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "FAILURE guest chat hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        app?.terminate()
    }

    func testGuestCanReadReplyAndSendLocallyWhileReactionPermissionFailureIsVisible() {
        openChat()
        let firstReply = app.buttons["Reply to Guest 2048"]
        reveal(firstReply)
        XCTAssertTrue(firstReply.isHittable)
        XCTAssertTrue(app.staticTexts["What a game!"].exists)
        capture("Guest chat reads the shared matchup without a sign-in gate")
        firstReply.tap()
        let composer = element("sports-chat-composer")
        reveal(composer)
        XCTAssertTrue(app.staticTexts["Replying to Guest 2048"].exists)
        composer.tap(); composer.typeText("Great defense!")
        let send = app.buttons["sports-chat-send"]
        reveal(send)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.staticTexts["Great defense!"].waitForExistence(timeout: 5))
        XCTAssertTrue(wait { (composer.value as? String ?? "") != "Great defense!" })
        XCTAssertFalse(app.staticTexts["Replying to Guest 2048"].exists)
        capture("Local guest reply keeps its quoted message and receives a guest identity")
        // Dismiss the keyboard without sending another message.
        app.navigationBars["Game chat"].tap()
        let react = app.buttons["React to Guest 2048"]
        reveal(react)
        react.tap()
        let fire = app.buttons["🔥"].firstMatch
        XCTAssertTrue(fire.waitForExistence(timeout: 5)); fire.tap()
        let error = element("sports-chat-action-error")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        reveal(error)
        XCTAssertTrue(app.staticTexts["Missing or insufficient permissions."].exists,
            "The local rule fixture must surface rejected updates rather than invent reaction success")
        XCTAssertTrue(app.buttons["Retry"].exists)
        capture("Guest chat shows the real reaction permission failure and Retry")
    }

    func testChatConnectionTimeoutOffersRetryAndAnIconCloseButton() {
        openChat()
        let close = app.buttons["sports-chat-close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.label, "Close chat")
        let failure = app.staticTexts["Chat isn’t responding. Check your connection and try again."]
        XCTAssertTrue(failure.waitForExistence(timeout: 18))
        XCTAssertFalse(app.staticTexts["Connecting to chat…"].exists)
        capture("Chat timeout has a clear close icon and an actionable retry")
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.isHittable); retry.tap()
        XCTAssertTrue(app.staticTexts["What a game!"].waitForExistence(timeout: 5))
        XCTAssertFalse(failure.exists)
        capture("Chat retry recovers without signing in or changing the game")
        close.tap()
        XCTAssertTrue(app.navigationBars["Game center"].waitForExistence(timeout: 5))
    }

    func testGuestComposerEnforcesTheThousandCharacterLimitBeforeSend() {
        openChat()
        let composer = element("sports-chat-composer")
        reveal(composer); composer.tap()
        composer.typeText(String(repeating: "a", count: 1001))
        XCTAssertTrue(wait { (composer.value as? String ?? "").utf16.count == 1000 })
        // SwiftUI localizes the interpolated integer in this visible counter.
        // The composer value above remains the strict UTF-16 boundary check.
        XCTAssertTrue(app.staticTexts["1,000/1,000"].exists)
        XCTAssertTrue(app.buttons["sports-chat-send"].isEnabled)
        capture("Guest composer caps input at the Android compatible thousand character limit")
    }

    private func openChat() {
        app.buttons["tab-sports"].tap()
        let center = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-'")).firstMatch
        reveal(center); center.tap()
        XCTAssertTrue(app.navigationBars["Game center"].waitForExistence(timeout: 8))
        let overview = app.buttons["sports-game-tab-Overview"]
        reveal(overview)
        let chat = app.buttons["sports-game-tab-Chat"]
        if !chat.isHittable {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let y = overview.frame.midY - app.frame.minY
            origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.15, dy: y)))
        }
        XCTAssertTrue(chat.isHittable); chat.tap()
        XCTAssertTrue(element("sports-chat").waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Game chat"].exists)
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
    }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<12 {
            if target.exists && target.isHittable { return }
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.55 : 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.25 : 0.55))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
