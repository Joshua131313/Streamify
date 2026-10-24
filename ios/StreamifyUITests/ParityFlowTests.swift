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

    func testRootTabsUseTapNavigationAndLeaveCarouselsIndependent() {
        let hero = element("hero-carousel")
        XCTAssertTrue(hero.waitForExistence(timeout: 12))
        if app.buttons["hero-carousel-pause"].label == "Pause carousel" { app.buttons["hero-carousel-pause"].tap() }
        for tab in ["sports", "search", "library", "home"] {
            app.buttons["tab-\(tab)"].tap()
            XCTAssertTrue(app.buttons["tab-\(tab)"].isSelected)
            XCTAssertTrue(app.staticTexts["root-title-\(tab)"].isHittable)
        }
        let title = app.staticTexts["root-title-home"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0)).withOffset(CGVector(dx: 0, dy: title.frame.midY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0)).withOffset(CGVector(dx: 0, dy: title.frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["tab-home"].isSelected, "A header drag must not switch root tabs.")
        let firstTitle = app.buttons["hero-main-progress"].label
        hero.swipeLeft()
        XCTAssertTrue(wait { self.app.buttons["hero-main-progress"].label != firstTitle })
        XCTAssertTrue(app.buttons["tab-home"].isSelected, "Carousel swipes must remain local to the carousel.")
        capture("Tap-only root navigation with continuous top and bottom backdrop")
    }

    func testExploreGenresPosterOpensItsExactMovieAndReturnsToRail() {
        pauseHomeCarousel()
        let rail = app.scrollViews["home-explore-genre"].firstMatch
        let poster = rail.buttons["explore-genre-media-movie:45"].firstMatch
        for _ in 0..<18 {
            if poster.exists && poster.isHittable && poster.frame.minY > app.frame.minY + 100 && poster.frame.maxY < app.frame.maxY - 110 { break }
            dragVertically(up: !(poster.exists && poster.frame.minY <= app.frame.minY + 100), in: app.scrollViews["home-catalog"].firstMatch)
        }
        XCTAssertTrue(rail.exists, "Explore genres must expose its own carousel instead of matching a duplicate title elsewhere.")
        XCTAssertTrue(poster.isHittable, "The actual genre poster must accept taps after scrolling Home.")
        let sourceFrame = poster.frame
        capture("Explore genres actual poster before tap")
        // Tap artwork rather than a title label or a generic duplicate media link.
        poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        XCTAssertTrue(element("media-detail-page").exists)
        XCTAssertTrue(app.buttons["download-movie:45"].waitForExistence(timeout: 8), "The tapped genre poster must open movie:45.")
        XCTAssertTrue(app.staticTexts["Beyond the City"].firstMatch.exists)
        capture("Explore genres exact selected movie details")
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(wait { poster.exists && poster.isHittable })
        XCTAssertEqual(poster.frame.minY, sourceFrame.minY, accuracy: 2)
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        capture("Explore genres preserved source position")
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
        pauseHomeCarousel()
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
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["browse-search"].exists, "Swiping or tapping the discovery tab must not open the search dialog automatically.")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["open-catalog-search-dialog"].tap()
        XCTAssertTrue(app.textFields["browse-search"].waitForExistence(timeout: 5))
        dismissTypingTutorial()
        capture("08 Dedicated search dialog with recents and type filters")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-search"].isHittable, "The search dialog owns typing without raising the root tab bar.")
        app.buttons["catalog-search-kind-movie"].tap()
        capture("08b Focused movie search")
        app.textFields["browse-search"].typeText("Horizon\n")
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(app.staticTexts["Search results"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["media-link-movie:42"].firstMatch.waitForExistence(timeout: 8))
        capture("09 Search results")
        app.buttons["media-link-movie:42"].firstMatch.tap()
        XCTAssertTrue(app.buttons["download-movie:42"].waitForExistence(timeout: 8), "A result must present its exact title from the dialog root.")
        app.buttons["close-media-details"].tap()
        XCTAssertEqual(app.textFields["browse-search"].value as? String, "Horizon")
        app.buttons["clear-catalog-search"].tap()
        XCTAssertTrue(app.staticTexts["Recent searches"].exists)
        app.buttons["catalog-search-kind-anime"].tap()
        app.textFields["browse-search"].typeText("Starlight\n")
        XCTAssertTrue(app.buttons["media-link-anime:44"].waitForExistence(timeout: 10))
        capture("09b Anime search in the same dialog")
        app.buttons["cancel-catalog-search"].tap()
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-search"].isSelected)
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
        XCTAssertTrue(app.staticTexts["detail-genre-28"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail-genre-28"].label, "Action")
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
        let historyResume = app.buttons["history-resume-tv:43"]
        reveal(historyResume)
        XCTAssertTrue(historyResume.isHittable)
        XCTAssertEqual(historyResume.frame.width, 128, accuracy: 1)
        XCTAssertEqual(historyResume.frame.height, 72, accuracy: 1)
        XCTAssertEqual(historyResume.frame.width / historyResume.frame.height, 16.0 / 9.0, accuracy: 0.02)
        XCTAssertLessThanOrEqual(element("history-card-tv:43").frame.height, 116, "History should use a compact row instead of a full-width image card.")
        let historyProgress = element("history-progress-tv:43")
        XCTAssertTrue(historyProgress.exists)
        XCTAssertGreaterThan(historyProgress.frame.minX, historyResume.frame.minX)
        XCTAssertLessThan(historyProgress.frame.maxX, historyResume.frame.maxX)
        XCTAssertEqual(historyProgress.value as? String, "11 percent", "History must show the saved playback position, not a fabricated progress value.")
        XCTAssertTrue(element("history-status-tv:43").label.contains("40 min left"))
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
        XCTAssertTrue(app.staticTexts["account-profile-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["account-profile-name"].label, "My profile")
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

    func testSportsMultiLeagueCalendarKeepsSelectionAndPosition() {
        app.buttons["tab-sports"].tap()
        let picker = app.buttons["sports-league-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertEqual(picker.value as? String, "All leagues")
        let firstGame = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-' AND identifier CONTAINS ':'")).firstMatch
        XCTAssertTrue(firstGame.waitForExistence(timeout: 10))
        XCTAssertLessThan(firstGame.frame.minY, app.frame.height * 0.55, "Compact controls must leave the first game visible near the top.")
        capture("43 Compact sports toolbar with game cards above the fold")
        picker.tap()
        XCTAssertTrue(app.buttons["sports-clear-leagues"].waitForExistence(timeout: 5))
        app.buttons["sports-clear-leagues"].tap()
        let apply = app.buttons["sports-apply-leagues"]
        XCTAssertTrue(apply.isEnabled, "Unchecked leagues mean all leagues, so Apply must remain available.")
        for league in ["nfl", "nba", "college-football", "wnba", "nhl", "mlb"] {
            XCTAssertFalse(app.buttons["sports-league-option-\(league)"].isSelected, "All leagues must start unchecked.")
        }
        app.buttons["sports-league-option-nfl"].tap()
        app.buttons["sports-league-option-nba"].tap()
        reveal(apply)
        XCTAssertTrue(apply.isEnabled)
        capture("43b Choose NFL and NBA together with small league logos")
        apply.tap()
        XCTAssertTrue(wait { !self.app.navigationBars["Filter leagues"].exists })
        XCTAssertEqual(picker.value as? String, "NFL, NBA")
        app.buttons["sports-date-picker"].tap()
        let tomorrow = app.buttons["sports-date-offset-1"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5))
        let initialY = tomorrow.frame.minY
        let initialX = tomorrow.frame.minX
        XCTAssertGreaterThanOrEqual(tomorrow.frame.height, 44, "Every calendar day needs a full touch target before selection.")
        XCTAssertTrue(app.buttons["sports-calendar-league-nfl"].isSelected)
        XCTAssertTrue(app.buttons["sports-calendar-league-nba"].isSelected)
        XCTAssertTrue(app.buttons["sports-calendar-league-nhl"].exists)
        XCTAssertFalse(app.buttons["sports-calendar-league-nhl"].isSelected)
        let wnbaLegend = app.buttons["sports-calendar-league-wnba"]
        wnbaLegend.tap()
        XCTAssertTrue(wait { wnbaLegend.isSelected })
        XCTAssertTrue(app.buttons["sports-calendar-league-nba"].isSelected)
        wnbaLegend.tap()
        XCTAssertTrue(wait { !wnbaLegend.isSelected })
        XCTAssertEqual(tomorrow.frame.minY, initialY, accuracy: 2, "Toggling a legend must not shift the calendar.")
        capture("44 NFL and NBA calendar sheet")
        tomorrow.tap()
        XCTAssertTrue(wait { tomorrow.isSelected })
        XCTAssertEqual(tomorrow.frame.minY, initialY, accuracy: 2, "Selecting a day must not move the calendar vertically.")
        XCTAssertEqual(tomorrow.frame.minX, initialX, accuracy: 2)
        app.buttons["sports-calendar-done"].tap()
        XCTAssertTrue(app.staticTexts["No games to show"].waitForExistence(timeout: 12))
        XCTAssertEqual(picker.value as? String, "NFL, NBA")
        capture("45 Compact empty-day result keeps selected leagues")
        app.buttons["sports-date-picker"].tap()
        let today = app.buttons["sports-date-offset-0"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        XCTAssertTrue(wait { today.isSelected })
        XCTAssertEqual(tomorrow.frame.minY, initialY, accuracy: 2, "Date changes must preserve the calendar position.")
        app.buttons["sports-calendar-done"].tap()
        XCTAssertTrue(wait { !self.app.staticTexts["No games to show"].exists && !self.element("sports-schedule-loading").exists })
        let nfl = app.buttons["sports-game-nfl:nfl-fixture"]
        let nba = app.buttons["sports-game-nba:nba-fixture"]
        reveal(nfl)
        XCTAssertTrue(nfl.isHittable, "The same selection must include NFL games.")
        reveal(nba)
        XCTAssertTrue(nba.isHittable, "The same selection must include NBA games.")
        capture("46 Combined NFL and NBA results")
        scrollSportsToTop()
        picker.tap()
        app.buttons["sports-clear-leagues"].tap()
        reveal(apply)
        apply.tap()
        XCTAssertTrue(wait { picker.value as? String == "All leagues" })
        capture("46b Clearing league choices restores all leagues")
        app.buttons["sports-date-picker"].tap()
        let nflLegend = app.buttons["sports-calendar-league-nfl"]
        XCTAssertFalse(nflLegend.isSelected)
        XCTAssertFalse(wnbaLegend.isSelected)
        wnbaLegend.tap()
        XCTAssertTrue(wait { wnbaLegend.isSelected })
        XCTAssertFalse(nflLegend.isSelected)
        capture("Calendar legend selects WNBA without losing other choices")
        wnbaLegend.tap()
        XCTAssertTrue(wait { !wnbaLegend.isSelected })
        app.buttons["sports-calendar-done"].tap()
        XCTAssertEqual(picker.value as? String, "All leagues", "Clearing the last calendar legend restores the unfiltered view.")
    }

    func testQuickLiveTogglePrioritizesLiveGamesAndRetainsOtherFilters() {
        app.buttons["tab-sports"].tap()
        selectSportsLeagues(["nba"])
        let live = app.buttons["sports-quick-live"]
        XCTAssertTrue(live.waitForExistence(timeout: 5))
        XCTAssertFalse(live.isSelected)
        live.tap()
        XCTAssertTrue(wait { live.isSelected })
        XCTAssertTrue((app.buttons["sports-filter-picker"].value as? String ?? "").contains("Live"))
        XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["sports-game-nba:nba-final"].exists)
        capture("Live games one-tap quick filter")
        app.buttons["sports-date-picker"].tap()
        app.buttons["sports-date-offset-1"].tap()
        app.buttons["sports-calendar-done"].tap()
        XCTAssertTrue(wait { !live.isEnabled && !live.isSelected })
        XCTAssertTrue((app.buttons["sports-filter-picker"].value as? String ?? "").contains("All games"))
        XCTAssertEqual(app.buttons["sports-league-picker"].value as? String, "NBA")
        capture("Future date clears and disables Live")
        app.buttons["sports-filter-picker"].tap()
        XCTAssertFalse(app.buttons["sports-filter-Live"].isEnabled)
        app.buttons["sports-filter-done"].tap()
        app.buttons["sports-date-picker"].tap()
        app.navigationBars["Game calendar"].buttons["Today"].tap()
        app.buttons["sports-calendar-done"].tap()
        XCTAssertTrue(wait { live.isEnabled && !live.isSelected })
        live.tap()
        XCTAssertTrue(wait { live.isSelected })
        live.tap()
        XCTAssertTrue(wait { !live.isSelected })
        XCTAssertTrue(app.buttons["sports-game-nba:nba-final"].waitForExistence(timeout: 8))
        app.buttons["sports-filter-picker"].tap()
        app.buttons["sports-filter-Final"].tap()
        app.buttons["sports-filter-done"].tap()
        XCTAssertFalse(live.isSelected)
        XCTAssertTrue(app.buttons["sports-game-nba:nba-final"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["sports-game-nba:nba-fixture"].exists)
        capture("Final results remain available from the filter sheet")
    }

    func testCollegeFootballLeagueOpensItsGameAndAvailableStream() {
        app.buttons["tab-sports"].tap()
        selectSportsLeagues(["college-football"])
        let game = app.buttons["sports-game-college-football:college-football-fixture"]
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        XCTAssertLessThan(game.frame.minY, app.frame.height * 0.55)
        capture("College football compact schedule")
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        watch.tap()
        XCTAssertTrue(app.buttons["sports-player-source-picker"].waitForExistence(timeout: 8))
        XCTAssertTrue((app.buttons["sports-player-source-picker"].value as? String ?? "").contains("alpha"))
        capture("College football available fixture stream")
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !self.app.buttons["Close player"].exists })
        XCTAssertEqual(app.buttons["sports-league-picker"].value as? String, "NCAAF")
    }

    func testScheduleDaySwipesKeepToolbarAndRootTabStationary() {
        app.buttons["tab-sports"].tap()
        selectSportsLeagues(["nba"])
        let date = app.buttons["sports-date-picker"]
        let originalDate = date.value as? String
        let originalToolbarY = date.frame.minY
        let live = app.buttons["sports-quick-live"]
        XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 10))
        live.tap()
        XCTAssertTrue(wait { live.isSelected })
        let heading = element("sports-schedule-heading")
        XCTAssertTrue(heading.exists)
        let leftStart = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        let leftEnd = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        leftStart.press(forDuration: 0.05, thenDragTo: leftEnd)
        XCTAssertTrue(wait { date.value as? String != originalDate && !live.isEnabled && !live.isSelected })
        XCTAssertEqual(date.frame.minY, originalToolbarY, accuracy: 2)
        XCTAssertEqual(app.buttons["sports-league-picker"].value as? String, "NBA")
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        XCTAssertFalse(app.buttons["Close player"].exists)
        capture("Swipe left advances the sports day beneath a stationary toolbar")
        let rightStart = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let rightEnd = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        rightStart.press(forDuration: 0.05, thenDragTo: rightEnd)
        XCTAssertTrue(wait { date.value as? String == originalDate && live.isEnabled })
        XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 10))
        XCTAssertEqual(date.frame.minY, originalToolbarY, accuracy: 2)
        // A drag over an explicit action must neither switch days nor invoke it.
        let gameCenter = app.buttons["Game Center"].firstMatch
        let protectedStart = gameCenter.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let protectedEnd = gameCenter.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        protectedStart.press(forDuration: 0.05, thenDragTo: protectedEnd)
        XCTAssertEqual(date.value as? String, originalDate)
        XCTAssertFalse(app.navigationBars["Game center"].exists, "Dragging inside Game Center must cancel its press, not open its sheet.")
        XCTAssertFalse(app.buttons["Close player"].exists)
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        capture("Swipe right returns to today without changing leagues or root tabs")
        gameCenter.tap()
        XCTAssertTrue(app.navigationBars["Game center"].waitForExistence(timeout: 5), "A normal tap immediately after the cancelled drag must still open Game Center.")
        app.buttons["Close"].tap()
        XCTAssertTrue(wait { !self.app.navigationBars["Game center"].exists && date.exists })
    }

    func testSportsScheduleScoringTableRosterChannelsAndMultiWatch() {
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(element("sports-screen").waitForExistence(timeout: 8))
        capture("30 Compact mixed-league sports schedule")
        app.buttons["focus-sports-search"].tap()
        XCTAssertTrue(element("sports-search-dialog").waitForExistence(timeout: 8))
        let sportsSearch = app.textFields["sports-dialog-search"]
        XCTAssertTrue(sportsSearch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Complete the simulator's first-use keyboard tutorial if present.
        let keyboardTutorial = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed up your typing")).firstMatch
        if keyboardTutorial.waitForExistence(timeout: 2) {
            let continueTyping = app.buttons["Continue"].firstMatch
            XCTAssertTrue(continueTyping.waitForExistence(timeout: 3))
            continueTyping.tap()
        }
        XCTAssertTrue(sportsSearch.isHittable)
        sportsSearch.typeText("NBA")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(app.staticTexts["Teams"].exists)
        XCTAssertTrue(app.buttons["sports-search-team-nba:200"].waitForExistence(timeout: 8))
        capture("30b Sports search dialog separates teams and games")
        app.buttons["sports-search-team-nba:200"].tap()
        XCTAssertTrue(app.buttons["sports-team-roster-tab"].waitForExistence(timeout: 8))
        capture("30c Sports search opens the exact team")
        app.navigationBars.buttons["Close"].tap()
        XCTAssertTrue(sportsSearch.waitForExistence(timeout: 5))
        XCTAssertEqual(sportsSearch.value as? String, "NBA")
        app.buttons["close-sports-search"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        // Search leaves the underlying league selection and scroll state alone.
        app.buttons["focus-sports-search"].tap()
        XCTAssertTrue(app.buttons["sports-search-recent-NBA"].waitForExistence(timeout: 5))
        capture("30d Recent sports searches")
        app.buttons["close-sports-search"].tap()
        selectSportsLeagues(["nba"])
        let game = app.buttons["sports-game-nba:nba-fixture"].firstMatch
        reveal(game)
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        capture("31 NBA schedule list")
        scrollSportsToTop()
        app.buttons["sports-filter-picker"].tap()
        app.buttons["sports-layout-Slider"].tap()
        app.buttons["sports-filter-done"].tap()
        capture("32 NBA schedule slider")
        app.buttons["sports-date-picker"].tap()
        XCTAssertTrue(element("sports-calendar-grid").waitForExistence(timeout: 5))
        capture("33 NBA schedule calendar sheet")
        app.buttons["sports-calendar-done"].tap()
        app.buttons["sports-filter-picker"].tap()
        app.buttons["sports-layout-List"].tap()
        app.buttons["sports-filter-done"].tap()
        reveal(game)
        game.tap()
        XCTAssertTrue(app.buttons["sports-scoring-tab"].waitForExistence(timeout: 8))
        capture("34 Game center overview")
        let watchGame = app.buttons["Watch game"]
        reveal(watchGame)
        XCTAssertTrue(watchGame.waitForExistence(timeout: 8))
        watchGame.tap()
        XCTAssertTrue(app.buttons["sports-player-source-picker"].waitForExistence(timeout: 8))
        capture("34b Live player source selector")
        app.buttons["sports-player-source-picker"].tap()
        XCTAssertTrue(app.buttons["sports-player-source-option-1"].waitForExistence(timeout: 5))
        app.buttons["sports-player-source-option-1"].tap()
        XCTAssertTrue(wait { (self.app.buttons["sports-player-source-picker"].value as? String ?? "").contains("bravo") })
        XCTAssertTrue(app.buttons["Close player"].exists, "Switching sources must keep the same player open.")
        capture("34c Live player switched source")
        let leavePlayerStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))
        leavePlayerStart.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45)))
        XCTAssertTrue(app.buttons["Close player"].isHittable, "Horizontal player interaction must preserve the current stream.")
        XCTAssertTrue((app.buttons["sports-player-source-picker"].value as? String ?? "").contains("bravo"))
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !self.app.buttons["Close player"].exists })
        XCTAssertTrue(app.buttons["sports-scoring-tab"].waitForExistence(timeout: 5))
        reveal(app.buttons["sports-scoring-tab"])
        app.buttons["sports-scoring-tab"].tap()
        XCTAssertTrue(element("sports-scoring-table").waitForExistence(timeout: 8))
        capture("35 Game period scoring table")
        app.buttons["sports-game-tab-Team stats"].tap()
        XCTAssertTrue(element("sports-comparison-table").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Field Goals"].exists)
        capture("35b Team comparison table")
        app.buttons["sports-team-200"].tap()
        XCTAssertTrue(app.buttons["sports-team-roster-tab"].waitForExistence(timeout: 8))
        app.buttons["sports-team-roster-tab"].tap()
        XCTAssertTrue(element("sports-team-roster").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Jordan Hayes"].exists)
        XCTAssertTrue(app.staticTexts["PLAYER"].exists)
        capture("36 Team roster table")
        relaunch()
        app.buttons["tab-sports"].tap()
        selectSportsLeagues(["nba"])
        let finalGame = app.buttons["sports-game-nba:nba-final"].firstMatch
        reveal(finalGame)
        XCTAssertTrue(finalGame.exists)
        XCTAssertFalse(app.staticTexts["WINNER"].exists)
        capture("36b Final score card emphasizes the winning score")
        finalGame.tap()
        XCTAssertTrue(app.buttons["sports-scoring-tab"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Winner"].exists)
        app.buttons["sports-scoring-tab"].tap()
        XCTAssertTrue(element("sports-scoring-total-200").waitForExistence(timeout: 8))
        XCTAssertTrue(element("sports-scoring-total-200").label.contains("winner"))
        XCTAssertEqual(element("sports-scoring-total-200").value as? String, "105")
        XCTAssertFalse(element("sports-scoring-total-100").label.contains("winner"))
        capture("36c Final scoring highlights the actual winner")
        relaunch()
        app.buttons["tab-sports"].tap()
        app.buttons["sports-menu"].tap()
        app.buttons["sports-channels"].tap()
        capture("37 Sports channel directory")
        scrollSportsToTop()
        app.buttons["sports-menu"].tap()
        app.buttons["sports-multi-watch"].tap()
        XCTAssertTrue(app.buttons["sports-multiwatch-add"].waitForExistence(timeout: 5))
        capture("38 Empty multi-watch")
        app.buttons["sports-multiwatch-add"].tap()
        XCTAssertTrue(element("sports-live-picker").waitForExistence(timeout: 8))
        capture("39 Live multi-watch picker")
        let liveChoice = app.buttons["sports-live-game-nba:nba-fixture"]
        XCTAssertTrue(liveChoice.waitForExistence(timeout: 10))
        reveal(liveChoice)
        liveChoice.tap()
        XCTAssertTrue(wait { !self.app.navigationBars["Add a game"].exists })
        let tileOptions = app.buttons["Options for BOS vs TOR"]
        XCTAssertTrue(tileOptions.waitForExistence(timeout: 8))
        capture("40 Multi-watch playing a local fixture")
        tileOptions.tap()
        XCTAssertTrue(app.buttons["Select stream"].waitForExistence(timeout: 5))
        app.buttons["Select stream"].tap()
        XCTAssertTrue(app.buttons["bravo 1 · English · HD"].waitForExistence(timeout: 5))
        app.buttons["bravo 1 · English · HD"].tap()
        XCTAssertTrue(tileOptions.waitForExistence(timeout: 5), "Changing a tile source must preserve its game and queue slot.")
        tileOptions.tap()
        app.buttons["Fullscreen"].tap()
        XCTAssertTrue(app.buttons["sports-player-source-picker"].waitForExistence(timeout: 8))
        XCTAssertTrue((app.buttons["sports-player-source-picker"].value as? String ?? "").contains("bravo"), "The tile's selected server must be retained when it expands.")
        capture("41 Expanded multi-watch retains its chosen server")
        let leaveExpandedStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))
        leaveExpandedStart.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45)))
        XCTAssertTrue(app.buttons["Close player"].isHittable, "Horizontal interaction must preserve the expanded multi-watch stream.")
        XCTAssertTrue((app.buttons["sports-player-source-picker"].value as? String ?? "").contains("bravo"))
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !self.app.buttons["Close player"].exists })
        XCTAssertTrue(tileOptions.waitForExistence(timeout: 5))
        capture("42 Closing the expanded player returns to the same multi-watch tile")
    }

    private func openTitle(_ key: String) {
        let field = app.textFields["browse-search"]
        if !field.exists {
            app.buttons["tab-search"].tap()
            XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
            app.buttons["open-catalog-search-dialog"].tap()
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            dismissTypingTutorial()
            field.typeText(key.hasPrefix("tv:") ? "Midnight Dispatch\n" : key.hasPrefix("anime:") ? "Starlight\n" : "Horizon\n")
        }
        let card = app.buttons.matching(identifier: "media-link-\(key)")
        XCTAssertTrue(wait(timeout: 12) { card.allElementsBoundByIndex.contains { $0.isHittable } })
        guard let target = card.allElementsBoundByIndex.first(where: { $0.isHittable }) else { XCTFail("No visible catalog card for \(key)"); return }
        target.tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        capture("Selected catalog card \(key)")
        let downloadKey = key.hasPrefix("tv:") ? "\(key):1:1" : key
        XCTAssertTrue(app.buttons["download-\(downloadKey)"].firstMatch.waitForExistence(timeout: 8), "A catalog card must open the title that was tapped.")
    }
    private func dismissTypingTutorial() {
        let tutorial = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Speed up your typing'")).firstMatch
        if tutorial.waitForExistence(timeout: 2) {
            let button = app.buttons["Continue"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.tap()
        }
    }
    private func relaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 12))
    }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func pauseHomeCarousel() {
        let pause = app.buttons["hero-carousel-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 12))
        if pause.label == "Pause carousel" { pause.tap() }
        XCTAssertEqual(pause.label, "Resume carousel", "Pause the unrelated live timeline before querying deep lazy content.")
    }
    private func reveal(_ target: XCUIElement, attempts: Int = 12) {
        for _ in 0..<attempts {
            if target.exists && target.isHittable { return }
            dragVertically(up: !(target.exists && target.frame.maxY < app.frame.midY))
        }
    }
    private func selectSportsLeagues(_ leagues: [String]) {
        scrollSportsToTop()
        let picker = app.buttons["sports-league-picker"]
        picker.tap()
        app.buttons["sports-clear-leagues"].tap()
        for league in leagues { app.buttons["sports-league-option-\(league)"].tap() }
        let apply = app.buttons["sports-apply-leagues"]
        reveal(apply)
        apply.tap()
        XCTAssertTrue(wait { !self.app.navigationBars["Filter leagues"].exists })
    }
    private func scrollSportsToTop() {
        let toolbar = app.buttons["sports-league-picker"]
        for _ in 0..<8 {
            if toolbar.exists && toolbar.isHittable { break }
            dragVertically(up: false, in: app.scrollViews["sports-screen"].firstMatch)
        }
        XCTAssertTrue(toolbar.isHittable, "Compact sports controls must remain reachable.")
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
