import XCTest

/// Complements the screen/navigation suite with applied control state. All data
/// and player documents are local fixtures; external provider availability is not tested.
final class ControlInteractionFlowTests: XCTestCase {
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
            capture("FAILURE controls")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE controls hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    func testHomeDiscoveryMenusApplyMediaProviderAndGenre() {
        pauseHomeCarousel()
        for mode in ["forYou", "trending", "provider", "genre"] {
            let media = app.buttons["home-choice-media-\(mode)"]
            reveal(media)
            XCTAssertTrue(media.label.contains("Movies"))
            media.tap()
            XCTAssertTrue(app.buttons["Series"].waitForExistence(timeout: 4))
            capture("Controls Home \(mode) media menu")
            app.buttons["Series"].tap()
            XCTAssertTrue(wait { media.label.contains("Series") })
            let show = app.buttons["explore-\(mode)-media-tv:43"]
            XCTAssertTrue(show.waitForExistence(timeout: 8), "Changing media type must replace this rail with series.")
            XCTAssertFalse(app.buttons["explore-\(mode)-media-movie:42"].exists)
            if mode == "provider" {
                let provider = app.buttons["home-choice-provider"]
                reveal(provider)
                provider.tap()
                XCTAssertTrue(app.buttons["Prime"].waitForExistence(timeout: 4))
                capture("Controls Home provider menu")
                app.buttons["Prime"].tap()
                XCTAssertTrue(wait { provider.label == "Provider, Prime" })
                XCTAssertTrue(show.waitForExistence(timeout: 8))
            }
            if mode == "genre" {
                let genre = app.buttons["home-choice-genre"]
                genre.tap()
                XCTAssertTrue(app.buttons["Drama"].waitForExistence(timeout: 4))
                capture("Controls Home genre menu")
                app.buttons["Drama"].tap()
                XCTAssertTrue(wait { genre.label == "Genre, Drama" })
                media.tap()
                app.buttons["Movies"].tap()
                XCTAssertTrue(wait { genre.label == "Genre, Action" }, "Switching kind must reset to a valid genre for that kind.")
                XCTAssertTrue(app.buttons["explore-genre-media-movie:42"].waitForExistence(timeout: 8))
            }
            capture("Controls Home \(mode) applied selections")
        }
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
    }

    func testCategoryGenreProviderAndSortControlsForEveryMediaKind() {
        for (title, kind) in [("Movies", "movie"), ("Shows", "tv"), ("Anime", "anime")] {
            if title != "Movies" { app.terminate(); app.launch() }
            XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 12))
            app.buttons[title].firstMatch.tap()
            XCTAssertTrue(app.scrollViews["category-catalog-\(kind)"].waitForExistence(timeout: 10))
            let genre = app.buttons["Genre, All genres"]
            XCTAssertTrue(genre.waitForExistence(timeout: 8))
            genre.tap()
            XCTAssertTrue(app.buttons["Drama"].waitForExistence(timeout: 5))
            capture("Controls \(title) genre menu")
            app.buttons["Drama"].tap()
            XCTAssertTrue(app.buttons["Genre, Drama"].waitForExistence(timeout: 5))
            if kind != "anime" {
                app.buttons["Provider, All providers"].tap()
                XCTAssertTrue(app.buttons["Netflix"].waitForExistence(timeout: 4))
                capture("Controls \(title) provider menu")
                app.buttons["Netflix"].tap()
                XCTAssertTrue(app.buttons["Provider, Netflix"].waitForExistence(timeout: 5))
            }
            let top = app.buttons["Top rated"]
            top.tap()
            XCTAssertTrue(wait { top.isSelected })
            XCTAssertFalse(app.buttons["Popular"].isSelected)
            capture("Controls \(title) genre provider and sort applied")
            app.buttons["Genre, Drama"].tap()
            app.buttons["All genres"].tap()
            XCTAssertTrue(app.buttons["Genre, All genres"].waitForExistence(timeout: 5))
            if kind != "anime" {
                app.buttons["Provider, Netflix"].tap()
                app.buttons["All providers"].tap()
                XCTAssertTrue(app.buttons["Provider, All providers"].waitForExistence(timeout: 5))
            }
            app.buttons["Popular"].tap()
            XCTAssertTrue(wait { self.app.buttons["Popular"].isSelected })
            XCTAssertFalse(top.isSelected)
            XCTAssertFalse(app.buttons["close-media-details"].exists)
            capture("Controls \(title) filters cleared")
        }
    }

    func testCollectionsGenreActuallyFiltersAndRestoresDirectory() {
        pauseHomeCarousel()
        let explore = app.buttons["Explore all"]
        reveal(explore)
        explore.tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 8))
        let filter = app.buttons["Filter collections by genre"]
        filter.tap()
        XCTAssertTrue(app.buttons["Drama"].waitForExistence(timeout: 4))
        capture("Controls collection genre menu")
        app.buttons["Drama"].tap()
        let darkKnight = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "The Dark Knight Trilogy")).firstMatch
        XCTAssertTrue(darkKnight.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Harry Potter")).firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Explore collection")).count, 1)
        capture("Controls collections Drama has one matching collection")
        filter.tap()
        app.buttons["All genres"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Harry Potter")).firstMatch.waitForExistence(timeout: 5))
        capture("Controls collections all genres restored")
    }

    func testLibraryKindFilterAndHistoryOverflowApplyToExactTitle() {
        app.buttons["tab-library"].tap()
        let filter = app.buttons["Filter library by type"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["Anime"].waitForExistence(timeout: 4))
        capture("Controls library media kind menu")
        app.buttons["Anime"].tap()
        XCTAssertTrue(element("poster-artwork-anime:44").waitForExistence(timeout: 5))
        XCTAssertFalse(element("poster-artwork-movie:42").exists)
        XCTAssertFalse(element("poster-artwork-tv:43").exists)
        capture("Controls library Anime filter applied")
        filter.tap()
        app.buttons["All titles"].tap()
        XCTAssertTrue(element("poster-artwork-movie:42").waitForExistence(timeout: 5))
        XCTAssertTrue(element("poster-artwork-tv:43").exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).firstMatch.tap()
        filter.tap()
        app.buttons["Anime"].tap()
        XCTAssertTrue(app.staticTexts["No matching titles"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your story starts here."].exists, "A filtered history must not claim the library has never been used.")
        capture("Controls library empty Anime history is a filter result")
        filter.tap()
        app.buttons["All titles"].tap()
        let actions = app.buttons["Actions for Midnight Dispatch"]
        reveal(actions)
        actions.tap()
        XCTAssertTrue(app.buttons["Remove from My list"].waitForExistence(timeout: 4))
        capture("Controls exact history title actions")
        app.buttons["Remove from My list"].tap()
        XCTAssertTrue(app.buttons["Saved · 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history-resume-tv:43"].exists, "Removing a saved title must preserve its watch history.")
        actions.tap()
        XCTAssertTrue(app.buttons["Add to My list"].waitForExistence(timeout: 4))
        app.buttons["Add to My list"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["Remove from history"].tap()
        XCTAssertTrue(app.buttons["History · 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["history-resume-tv:43"].exists)
        XCTAssertTrue(app.buttons["history-resume-movie:42"].exists)
        XCTAssertTrue(app.buttons["Saved · 3"].exists)
        capture("Controls history removal preserves saved list and other history")
    }

    func testAppearanceAndFavoriteGenreSelectionPersistAcrossPresentation() {
        app.buttons["tab-library"].tap()
        openSettings()
        let themes = app.segmentedControls.firstMatch
        XCTAssertTrue(themes.waitForExistence(timeout: 5))
        for name in ["Light", "System", "Dark"] {
            themes.buttons[name].tap()
            XCTAssertTrue(wait { themes.buttons[name].isSelected })
            capture("Controls appearance \(name)")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["tab-library"].isSelected)
            XCTAssertTrue(app.buttons["tab-home"].isHittable)
            capture("Root navigation follows \(name) appearance")
            openSettings()
            XCTAssertTrue(themes.buttons[name].isSelected)
        }
        app.buttons["Done"].tap()
        openSettings()
        XCTAssertTrue(app.segmentedControls.buttons["Dark"].isSelected)
        app.buttons["Account & preferences"].tap()
        let preferences = app.buttons["Your favorite genres"]
        reveal(preferences)
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))
        let comedy = app.buttons["Comedy"]
        let initiallySelected = comedy.isSelected
        comedy.tap()
        XCTAssertTrue(wait { comedy.isSelected != initiallySelected })
        capture("Controls favorite genre selected")
        app.navigationBars["Preferences"].buttons.firstMatch.tap()
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(comedy.isSelected, !initiallySelected)
        comedy.tap()
        XCTAssertTrue(wait { comedy.isSelected == initiallySelected })
        capture("Controls favorite genre retained and restored")
    }

    func testSportsDraftCancelUpcomingFollowingAndTodayReset() {
        app.buttons["tab-sports"].tap()
        let leagues = app.buttons["sports-league-picker"]
        XCTAssertTrue(leagues.waitForExistence(timeout: 8))
        leagues.tap()
        app.buttons["sports-clear-leagues"].tap()
        app.buttons["sports-league-option-nba"].tap()
        capture("Controls sports draft league selection")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(leagues.value as? String, "All leagues", "Cancelling must discard the draft selection.")
        leagues.tap()
        app.buttons["sports-clear-leagues"].tap()
        app.buttons["sports-league-option-nba"].tap()
        reveal(app.buttons["sports-apply-leagues"])
        app.buttons["sports-apply-leagues"].tap()
        XCTAssertTrue(wait { leagues.value as? String == "NBA" })
        for filter in ["Upcoming", "Following", "All games"] {
            app.buttons["sports-filter-picker"].tap()
            let option = app.buttons["sports-filter-\(filter)"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            XCTAssertTrue(option.isSelected)
            capture("Controls sports \(filter) selected in filter sheet")
            app.buttons["sports-filter-done"].tap()
            XCTAssertTrue(wait { (self.app.buttons["sports-filter-picker"].value as? String ?? "").contains(filter) })
            if filter == "Upcoming" {
                XCTAssertTrue(app.staticTexts["No games to show"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["sports-game-nba:nba-fixture"].exists)
            } else if filter == "Following" {
                XCTAssertTrue(app.staticTexts["No followed teams playing"].waitForExistence(timeout: 10))
            } else {
                XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 10))
            }
            capture("Controls sports \(filter) applied result")
        }
        app.buttons["sports-date-picker"].tap()
        let tomorrow = app.buttons["sports-date-offset-1"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5))
        tomorrow.tap()
        XCTAssertTrue(wait { tomorrow.isSelected })
        capture("Controls sports calendar tomorrow selected")
        app.navigationBars["Game calendar"].buttons["Today"].tap()
        XCTAssertTrue(wait { self.app.buttons["sports-date-offset-0"].isSelected })
        XCTAssertFalse(tomorrow.isSelected)
        app.buttons["sports-calendar-done"].tap()
        XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 10))
        XCTAssertEqual(leagues.value as? String, "NBA")
        capture("Controls sports Today reset preserves NBA")
    }

    func testSearchFieldAndHeaderPresentFullSearchAndReturnToTheirOriginalContext() {
        app.buttons["tab-search"].tap()
        let fieldSource = app.buttons["open-catalog-search-dialog"]
        XCTAssertTrue(fieldSource.waitForExistence(timeout: 8))
        let series = app.buttons["Series"].firstMatch
        series.tap()
        XCTAssertTrue(wait { series.isSelected })
        let sourceFrame = fieldSource.frame
        fieldSource.tap()
        let catalogInput = app.textFields["browse-search"]
        XCTAssertTrue(catalogInput.waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Typing should begin after the native presentation finishes.")
        dismissSearchKeyboardTutorial()
        XCTAssertTrue(catalogInput.isHittable)
        XCTAssertTrue(app.buttons["catalog-search-kind-tv"].isSelected)
        XCTAssertFalse(app.buttons["tab-search"].isHittable, "The full search screen owns typing without raising the bottom navigation.")
        capture("Search input expands into the dedicated full search screen")
        catalogInput.typeText("Midnight\n")
        XCTAssertTrue(app.buttons["media-link-tv:43"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["cancel-catalog-search"].tap()
        XCTAssertTrue(wait { fieldSource.isHittable && series.isSelected })
        XCTAssertTrue(wait { abs(fieldSource.frame.minY - sourceFrame.minY) < 1 && abs(fieldSource.frame.width - sourceFrame.width) < 1 })
        XCTAssertTrue(app.buttons["tab-search"].isSelected)
        capture("Cancel returns to the same search field and Series discovery filter")

        let catalogHeader = app.buttons["open-catalog-search"].firstMatch
        XCTAssertTrue(catalogHeader.isHittable)
        catalogHeader.tap()
        XCTAssertTrue(catalogInput.waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["tab-home"].isHittable)
        capture("Catalog header icon expands into full search")
        app.buttons["cancel-catalog-search"].tap()
        XCTAssertTrue(wait { catalogHeader.isHittable && fieldSource.isHittable })
    }

    func testSportsSearchReturnsToItsSelectedLeaguesAndFutureDate() {
        // Keep this independent from the catalogue flow: each covers its own
        // presentation context within XCTest's per-test execution allowance.
        app.buttons["tab-sports"].tap()
        let leagues = app.buttons["sports-league-picker"]
        XCTAssertTrue(leagues.waitForExistence(timeout: 8))
        leagues.tap()
        app.buttons["sports-clear-leagues"].tap()
        app.buttons["sports-league-option-nba"].tap()
        app.buttons["sports-apply-leagues"].tap()
        XCTAssertTrue(wait { leagues.value as? String == "NBA" })
        let date = app.buttons["sports-date-picker"]
        date.tap()
        XCTAssertTrue(app.buttons["sports-date-offset-1"].waitForExistence(timeout: 8))
        app.buttons["sports-date-offset-1"].tap()
        app.buttons["sports-calendar-done"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let selectedDate = date.value as? String
        app.buttons["focus-sports-search"].tap()
        let sportsInput = app.textFields["sports-dialog-search"]
        XCTAssertTrue(sportsInput.waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        dismissSearchKeyboardTutorial()
        XCTAssertTrue(sportsInput.isHittable)
        XCTAssertFalse(app.buttons["tab-sports"].isHittable)
        capture("Sports header icon expands into focused full search")
        sportsInput.typeText("NBA\n")
        app.buttons["close-sports-search"].tap()
        XCTAssertTrue(wait { date.isHittable && self.app.buttons["focus-sports-search"].isHittable })
        XCTAssertEqual(date.value as? String, selectedDate)
        XCTAssertEqual(leagues.value as? String, "NBA")
        XCTAssertFalse(app.buttons["sports-quick-live"].isEnabled)
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        capture("Search cancel preserves selected leagues and future game date")
    }

    func testOnlinePlayerProviderModeAndSeasonPickerApply() {
        app.buttons["tab-library"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).firstMatch.tap()
        let resume = app.buttons["history-resume-tv:43"]
        reveal(resume)
        resume.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.staticTexts["Streamify preview player"].waitForExistence(timeout: 8))
        XCTAssertTrue(wait { !self.playbackDocument().isEmpty })
        let firstDocument = playbackDocument()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vidy")).firstMatch.tap()
        XCTAssertTrue(app.buttons["StreamEx"].waitForExistence(timeout: 4))
        capture("Controls online provider menu")
        app.buttons["StreamEx"].tap()
        let chosenProvider = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "StreamEx")).firstMatch
        XCTAssertTrue(chosenProvider.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { self.playbackDocument() != firstDocument && !self.playbackDocument().isEmpty }, "The selected provider must load a new player document.")
        app.buttons["Switch to direct mode"].tap()
        XCTAssertTrue(app.buttons["Switch to embed mode"].waitForExistence(timeout: 5))
        app.buttons["Switch to embed mode"].tap()
        XCTAssertTrue(app.buttons["Switch to direct mode"].waitForExistence(timeout: 5))
        app.buttons["Episodes"].tap()
        XCTAssertTrue(app.navigationBars["Episodes"].waitForExistence(timeout: 5))
        let season = app.buttons.matching(NSPredicate(format: "label == %@ OR label CONTAINS %@ OR value == %@", "Season", "Season 1", "Season 1")).firstMatch
        XCTAssertTrue(season.waitForExistence(timeout: 5))
        XCTAssertTrue(season.label.contains("Season 1") || (season.value as? String ?? "").contains("Season 1"))
        season.tap()
        XCTAssertTrue(app.buttons["Season 2"].waitForExistence(timeout: 4))
        capture("Controls online season picker")
        app.buttons["Season 2"].tap()
        let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "3. A New Horizon")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 8))
        capture("Controls second season episodes")
        episode.tap()
        XCTAssertTrue(app.staticTexts["Season 2 · Episode 3"].waitForExistence(timeout: 8))
        XCTAssertTrue(chosenProvider.exists, "Episode changes must retain the chosen provider.")
        XCTAssertFalse(app.buttons["Next episode"].exists, "The last episode of the final fixture season has no next episode.")
        app.buttons["Episodes"].tap()
        let retainedSeason = app.buttons.matching(NSPredicate(format: "label == %@ OR label CONTAINS %@ OR value == %@", "Season", "Season 2", "Season 2")).firstMatch
        XCTAssertTrue(retainedSeason.waitForExistence(timeout: 5))
        XCTAssertTrue(retainedSeason.label.contains("Season 2") || (retainedSeason.value as? String ?? "").contains("Season 2"))
        capture("Controls player retains selected season and source")
        app.buttons["Done"].tap()
        app.buttons["Close player"].tap()
    }

    func testOfflineTracksPanelSpeedAndPictureFitControls() {
        app.buttons["open-downloads"].tap()
        let playFile = app.buttons["download-play-00000000-0000-0000-0000-000000000042"]
        XCTAssertTrue(playFile.waitForExistence(timeout: 8))
        playFile.tap()
        let play = app.buttons["offline-play-pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" })
        revealOfflineControls(play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        let tracks = app.buttons["offline-audio-subtitles"]
        revealOfflineControls(tracks)
        tracks.tap()
        XCTAssertTrue(app.staticTexts["This file has no alternate audio tracks."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This file has no embedded subtitles."].exists)
        XCTAssertTrue(app.buttons["Import SRT or VTT file"].exists)
        capture("Controls offline actual file audio and subtitle options")
        app.buttons["Done"].tap()
        let fill = app.buttons["Fill screen"]
        revealOfflineControls(fill)
        fill.tap()
        XCTAssertTrue(app.buttons["Fit picture"].waitForExistence(timeout: 5))
        app.buttons["Fit picture"].tap()
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        app.buttons["offline-speed"].tap()
        XCTAssertTrue(app.buttons["offline-rate-0.75"].waitForExistence(timeout: 5))
        capture("Controls offline playback speed panel")
        app.buttons["offline-rate-0.75"].tap()
        XCTAssertTrue(wait { self.app.buttons["offline-speed"].label.contains("0.75") })
        app.buttons["offline-speed"].tap()
        XCTAssertTrue(app.buttons["offline-rate-0.75"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["offline-rate-0.75"].isSelected)
        XCTAssertFalse(app.buttons["offline-rate-1.0"].isSelected)
        capture("Controls offline chosen speed retained")
        app.buttons["Done"].tap()
        XCTAssertEqual(play.label, "Play", "Opening controls must not resume a paused video.")
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
    }

    private func openSettings() {
        let more = app.buttons["More options"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func dismissSearchKeyboardTutorial() {
        let tutorial = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed up your typing")).firstMatch
        if tutorial.waitForExistence(timeout: 2) {
            let next = app.buttons["Continue"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            next.tap()
        }
    }

    private func pauseHomeCarousel() {
        let pause = app.buttons["hero-carousel-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 12))
        if pause.label == "Pause carousel" { pause.tap() }
        XCTAssertEqual(pause.label, "Resume carousel")
    }

    private func playbackDocument() -> String {
        let nonce = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback session ")).firstMatch
        return nonce.exists ? nonce.label : ""
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<15 {
            if target.exists && target.isHittable { return }
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.78 : 0.28))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable, "The requested control must be reachable.")
    }

    private func revealOfflineControls(_ target: XCUIElement) {
        if !target.exists || !target.isHittable {
            let canvas = app.otherElements["Offline video"].firstMatch
            XCTAssertTrue(canvas.waitForExistence(timeout: 5))
            canvas.tap()
            XCTAssertTrue(target.waitForExistence(timeout: 3))
        }
        XCTAssertTrue(target.isHittable)
    }

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
