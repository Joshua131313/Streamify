import XCTest

/// Exercises the shipped navigation with URLProtocol data and local WebKit documents.
/// These tests verify UI behavior; they make no assertion about live provider playback.
final class ParityFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE current screen")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
    }

    func testHomeHeroProgressPauseSwipeAndFilledSelectors() {
        let progress = app.buttons["hero-main-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        reveal(progress)
        capture("01 Home populated")
        let firstValue = progress.value as? String
        XCTAssertTrue(wait { progress.value as? String != firstValue }, "The selected hero indicator must advance over time.")
        app.buttons["hero-carousel-pause"].tap()
        XCTAssertEqual(app.buttons["hero-carousel-pause"].label, "Resume carousel")
        XCTAssertTrue((progress.value as? String ?? "").contains("paused"))
        capture("02 Hero paused")
        app.buttons["hero-carousel-pause"].tap()
        let priorTitle = progress.label
        element("hero-carousel").swipeLeft()
        XCTAssertTrue(wait { self.app.buttons["hero-main-progress"].label != priorTitle })
        capture("03 Hero swipe and animated indicator")
        let choice = app.buttons["home-choice-media-forYou"]
        reveal(choice)
        XCTAssertTrue(choice.isHittable)
        capture("04 Home filled selectors")
        choice.tap()
        XCTAssertTrue(app.buttons["Movies"].firstMatch.waitForExistence(timeout: 5))
        capture("05 Home media selector menu")
    }

    func testMovieShowAnimeCategoriesAndSearch() {
        for (title, kind) in [("Movies", "movie"), ("Shows", "tv"), ("Anime", "anime")] {
            if title != "Movies" { relaunch() }
            app.buttons[title].firstMatch.tap()
            let catalog = app.scrollViews["category-catalog-\(kind)"].firstMatch
            XCTAssertTrue(catalog.waitForExistence(timeout: 12))
            let expected = kind == "movie" ? "media-link-movie:42" : kind == "tv" ? "media-link-tv:43" : "media-link-anime:44"
            XCTAssertTrue(app.buttons[expected].firstMatch.waitForExistence(timeout: 12))
            capture("06 Category \(title) hero and controls")
            let gridHeading = app.staticTexts["Explore \(title)"]
            let key = kind == "movie" ? "movie:42" : kind == "tv" ? "tv:43" : "anime:44"
            let gridPoster = catalog.descendants(matching: .any).matching(identifier: "poster-artwork-\(key)").firstMatch
            for _ in 0..<5 {
                if gridHeading.isHittable && gridPoster.isHittable { break }
                dragVertically(up: true, in: catalog)
                XCTAssertFalse(app.buttons["close-media-details"].exists, "Scrolling a catalog must not activate its hero card.")
            }
            XCTAssertTrue(gridHeading.isHittable)
            XCTAssertTrue(gridPoster.isHittable, "The category's actual poster grid must be visible after scrolling.")
            XCTAssertTrue(catalog.exists)
            XCTAssertFalse(app.buttons["close-media-details"].exists)
            capture("07 Category \(title) poster grid")
        }
        relaunch()
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.textFields["browse-search"].waitForExistence(timeout: 5))
        capture("08 Search recent and discovery")
        app.textFields["browse-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { !self.app.buttons["tab-search"].exists }, "The bottom navigation must stay hidden while typing, rather than rise above the keyboard.")
        capture("08b Search typing without floating navigation")
        app.textFields["browse-search"].typeText("Horizon\n")
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(app.buttons["tab-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-search"].isSelected)
        XCTAssertTrue(app.staticTexts["Search results"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["media-link-movie:42"].firstMatch.waitForExistence(timeout: 8))
        capture("09 Search results")
    }

    func testMovieTrailerDownloadQualityCastSheetAndDragReturn() {
        // The hero and several shelves contain this title. Select its hero page and
        // address the hero's distinct label instead of the first off-screen shelf.
        let firstSlide = app.buttons["Show The Last Horizon"].firstMatch
        XCTAssertTrue(firstSlide.waitForExistence(timeout: 15))
        if app.buttons["hero-carousel-pause"].label == "Pause carousel" { app.buttons["hero-carousel-pause"].tap() }
        firstSlide.tap()
        let originalHomeCard = app.buttons["Details for The Last Horizon"].firstMatch
        capture("10a Original Home card before opening")
        XCTAssertTrue(wait { originalHomeCard.isHittable })
        originalHomeCard.tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        XCTAssertGreaterThan(app.buttons["close-media-details"].frame.midX, app.frame.midX, "The secondary close control belongs at the top right.")
        XCTAssertGreaterThanOrEqual(app.buttons["close-media-details"].frame.width, 44)
        XCTAssertTrue(app.buttons["download-movie:42"].waitForExistence(timeout: 8), "The tapped Home hero must open its own movie.")
        XCTAssertTrue(app.webViews.staticTexts["Playing preview"].waitForExistence(timeout: 8), "The visible detail preview must actually receive the autoplay command.")
        XCTAssertFalse(app.buttons["trailer-mute"].exists, "The autoplay preview must not add a separate controls strip.")
        capture("10 Movie autoplay preview and download action")
        let download = app.buttons["download-movie:42"]
        reveal(download)
        download.tap()
        XCTAssertTrue(app.buttons["720p download quality"].waitForExistence(timeout: 5))
        app.buttons["720p download quality"].tap()
        XCTAssertTrue(app.buttons["720p download quality"].isSelected)
        capture("11 Movie download quality choices")
        reveal(app.buttons["start-media-download"])
        app.buttons["start-media-download"].tap()
        XCTAssertTrue(element("download-error").waitForExistence(timeout: 10))
        XCTAssertTrue(element("download-error").label.contains("streaming only"))
        reveal(element("download-error"))
        capture("12 Honest stream-only download result")
        app.buttons["Close"].firstMatch.tap()
        reveal(app.buttons["cast-91"])
        app.buttons["cast-91"].tap()
        let castProfile = app.navigationBars["Cast profile"]
        XCTAssertTrue(castProfile.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Alex Morgan is an actor'")).firstMatch.waitForExistence(timeout: 8))
        capture("13 Cast vertical sheet")
        castProfile.buttons["Close"].tap()
        XCTAssertTrue(wait { !castProfile.exists })
        XCTAssertTrue(app.buttons["cast-91"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["close-media-details"].exists)
        capture("14 Cast dismissal preserves movie detail")
        // Reset scroll to the hero, then exercise UIKit's native zoom dismissal gesture.
        for _ in 0..<5 {
            if !app.buttons["close-media-details"].exists || app.webViews.firstMatch.isHittable { break }
            dragVertically(up: false)
        }
        if app.buttons["close-media-details"].exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(wait { !self.app.buttons["close-media-details"].exists }, "Dragging the detail card down should return to the original catalog card.")
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        XCTAssertTrue(originalHomeCard.exists)
        XCTAssertTrue(originalHomeCard.isHittable)
        capture("15 Native card return to original catalog")
    }

    func testShowEpisodeDownloadsAndPlayerEpisodePicker() {
        openTitle("tv:43")
        capture("16 Show detail preview")
        let episodeDownload = app.buttons["download-tv:43:1:2"]
        reveal(episodeDownload)
        XCTAssertTrue(episodeDownload.exists, "Every TV episode needs its own download action.")
        capture("17 Show episodes with individual download actions")
        episodeDownload.tap()
        XCTAssertTrue(app.staticTexts["Season 1 · Episode 2"].waitForExistence(timeout: 5))
        capture("18 Episode-specific download quality")
        app.buttons["Close"].firstMatch.tap()
        app.buttons["close-media-details"].tap()
        openTitle("tv:43")
        let watch = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Watch'")).firstMatch
        reveal(watch)
        XCTAssertTrue(watch.exists)
        watch.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Reload player"].exists)
        capture("19 Player native chrome and local fixture")
        app.buttons["Episodes"].tap()
        XCTAssertTrue(app.navigationBars["Episodes"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Missing Signal'")).firstMatch.waitForExistence(timeout: 8))
        capture("20 Player episode picker")
        app.buttons["Done"].tap()
        app.buttons["Next episode"].tap()
        XCTAssertTrue(app.staticTexts["Season 1 · Episode 2"].waitForExistence(timeout: 5))
        app.buttons["Close player"].tap()
    }

    func testLibraryPosterDimensionsDownloadsSettingsAccountAndCollections() {
        app.buttons["tab-library"].tap()
        let first = element("poster-artwork-anime:44")
        let second = element("poster-artwork-tv:43")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        capture("21 My list uniform poster images")
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        XCTAssertEqual(first.frame.width / first.frame.height, 2.0 / 3.0, accuracy: 0.01)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Resume Midnight Dispatch"].waitForExistence(timeout: 5))
        capture("22 Watch history")
        app.buttons["open-downloads"].tap()
        XCTAssertTrue(app.buttons["Add link"].waitForExistence(timeout: 5))
        capture("23 Downloads empty state and entry points")
        app.buttons["Add link"].tap()
        XCTAssertTrue(app.navigationBars["Add video"].waitForExistence(timeout: 5))
        capture("24 Add video link")
        app.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        app.buttons["More options"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["save-settings"].waitForExistence(timeout: 5))
        capture("25 Settings")
        let updates = app.buttons["App updates"]
        reveal(updates)
        updates.tap()
        XCTAssertTrue(app.buttons["check-ios-updates"].waitForExistence(timeout: 5))
        reveal(app.buttons["check-ios-updates"])
        app.buttons["check-ios-updates"].tap()
        XCTAssertTrue(app.staticTexts["No iOS updates have been published yet."].waitForExistence(timeout: 8))
        capture("25b App updates with no published release")
        app.navigationBars.buttons.firstMatch.tap()
        // Dismiss without saving fixture credentials into the real Keychain.
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 5))
        app.buttons["More options"].tap()
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Make yourself at home."].waitForExistence(timeout: 5))
        capture("26 Account")
        app.buttons["Your favorite genres"].tap()
        XCTAssertTrue(app.staticTexts["What do you love?"].waitForExistence(timeout: 5))
        app.buttons["Action"].tap()
        XCTAssertTrue(app.buttons["Action"].isSelected)
        capture("27 Genre preferences")
        relaunch()
        let explore = app.buttons["Explore all"]
        reveal(explore)
        explore.tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 5))
        capture("28 Collections directory")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Explore collection'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["3 movies · Release order"].waitForExistence(timeout: 8))
        capture("29 Collection detail and posters")
    }

    func testSportsScheduleScoringTableRosterChannelsAndMultiWatch() {
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(element("sports-screen").waitForExistence(timeout: 8))
        capture("30 Sports league directory")
        app.buttons["focus-sports-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // A fresh iOS simulator can show QuickPath's introductory card in
        // place of the keys. Finish that tutorial before exercising submission.
        let keyboardTutorial = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed up your typing")).firstMatch
        if keyboardTutorial.waitForExistence(timeout: 2) {
            let continueTyping = app.buttons["Continue"].firstMatch
            XCTAssertTrue(continueTyping.waitForExistence(timeout: 3))
            continueTyping.tap()
        }
        XCTAssertTrue(app.keyboards.buttons["Search"].waitForExistence(timeout: 5))
        XCTAssertTrue(wait { !self.app.buttons["tab-sports"].exists })
        XCTAssertTrue(app.textFields["sports-search-field"].isHittable)
        capture("30b Sports header search stays in Sports")
        // The keyboard accessory also dismisses an empty query without
        // submitting a search or changing tabs.
        XCTAssertTrue(app.buttons["dismiss-sports-search"].waitForExistence(timeout: 5))
        app.buttons["dismiss-sports-search"].tap()
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        app.buttons["focus-sports-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.textFields["sports-search-field"].typeText("NBA")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        XCTAssertEqual(app.textFields["sports-search-field"].value as? String, "NBA")
        app.buttons["Clear sports search"].tap()
        reveal(app.buttons["sports-league-NBA"])
        app.buttons["sports-league-NBA"].tap()
        let game = app.buttons["sports-game-nba:nba-fixture"].firstMatch
        reveal(game)
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        capture("31 NBA schedule list")
        scrollSportsToTop()
        reveal(app.buttons["sports-layout-Slider"])
        app.buttons["sports-layout-Slider"].tap()
        capture("32 NBA schedule slider")
        app.buttons["sports-layout-Calendar"].tap()
        capture("33 NBA schedule calendar")
        app.buttons["sports-layout-List"].tap()
        reveal(game)
        game.tap()
        XCTAssertTrue(app.buttons["sports-scoring-tab"].waitForExistence(timeout: 8))
        capture("34 Game center overview")
        app.buttons["sports-scoring-tab"].tap()
        XCTAssertTrue(element("sports-scoring-table").waitForExistence(timeout: 8))
        capture("35 Game period scoring table")
        app.buttons["sports-team-200"].tap()
        XCTAssertTrue(app.buttons["sports-team-roster-tab"].waitForExistence(timeout: 8))
        app.buttons["sports-team-roster-tab"].tap()
        XCTAssertTrue(element("sports-team-roster").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Jordan Hayes"].exists)
        capture("36 Team roster table")
        relaunch()
        app.buttons["tab-sports"].tap()
        element("sports-league-directory").swipeLeft()
        element("sports-league-directory").swipeLeft()
        reveal(app.buttons["sports-channels"])
        app.buttons["sports-channels"].tap()
        capture("37 Sports channel directory")
        scrollSportsToTop()
        app.buttons["sports-multi-watch"].tap()
        XCTAssertTrue(app.buttons["sports-multiwatch-add"].waitForExistence(timeout: 5))
        capture("38 Empty multi-watch")
        app.buttons["sports-multiwatch-add"].tap()
        XCTAssertTrue(element("sports-live-picker").waitForExistence(timeout: 8))
        capture("39 Live multi-watch picker")
    }

    private func openTitle(_ key: String) {
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.textFields["browse-search"].waitForExistence(timeout: 5))
        let card = app.buttons.matching(identifier: "media-link-\(key)")
        XCTAssertTrue(wait(timeout: 12) { card.allElementsBoundByIndex.contains { $0.isHittable } })
        guard let target = card.allElementsBoundByIndex.first(where: { $0.isHittable }) else { XCTFail("No visible catalog card for \(key)"); return }
        target.tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        capture("Selected catalog card \(key)")
        let downloadKey = key.hasPrefix("tv:") ? "\(key):1:1" : key
        XCTAssertTrue(app.buttons["download-\(downloadKey)"].firstMatch.waitForExistence(timeout: 8), "A catalog card must open the title that was tapped.")
    }
    private func relaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 12))
    }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func reveal(_ target: XCUIElement, attempts: Int = 12) {
        for _ in 0..<attempts {
            if target.exists && target.isHittable { return }
            dragVertically(up: !(target.exists && target.frame.maxY < app.frame.midY))
        }
    }
    private func scrollSportsToTop() {
        let search = app.textFields["sports-search-field"]
        let multiWatch = app.buttons["sports-multi-watch"]
        for _ in 0..<8 {
            if search.exists && search.isHittable && multiWatch.exists && multiWatch.isHittable { break }
            dragVertically(up: false, in: app.scrollViews["sports-screen"].firstMatch)
        }
        XCTAssertTrue(search.isHittable, "Return to the sports header before locating controls above the schedule.")
        XCTAssertTrue(multiWatch.isHittable)
    }
    private func dragVertically(up: Bool, in scrollView: XCUIElement? = nil) {
        // Use the content gutter, away from image buttons and nested horizontal rails.
        // An ancestor accessibility ID can also occur on a child button; do not ask
        // that ambiguous element to synthesize a swipe at its own activation point.
        let surface = scrollView ?? app!
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.78 : 0.28))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.28 : 0.78))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    private func wait(timeout: TimeInterval = 8, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
