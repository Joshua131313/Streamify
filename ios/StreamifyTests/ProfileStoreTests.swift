import Foundation
import XCTest
@testable import Streamify

final class ProfileStoreTests: XCTestCase {
    @MainActor
    func testGuestLibraryMigratesOnceIntoOnlyTheOriginalProfile() throws {
        try withDefaults { defaults in
            let guest = LibraryStore(defaults: defaults)
            let movie = title(42, .movie)
            guest.toggleSaved(movie)
            guest.record(movie, positionSeconds: 125, durationSeconds: 1800)
            guest.rememberSearch("Original search")
            guest.toggleTeam("nba:13")
            guest.setGenre(18)
            let legacyBytes = defaults.data(forKey: "streamify.ios.guestLibrary.v1")

            let store = ProfileStore(defaults: defaults)
            let original = try XCTUnwrap(store.activeProfile)
            XCTAssertTrue(store.library.isSaved(movie))
            XCTAssertEqual(store.library.history.first?.positionSeconds, 125)
            XCTAssertEqual(store.library.recentSearches, ["Original search"])
            XCTAssertEqual(store.library.followedTeams, ["nba:13"])
            XCTAssertEqual(store.library.favoriteGenres, [18])
            XCTAssertEqual(defaults.data(forKey: "streamify.ios.guestLibrary.v1"), legacyBytes, "Migration retains the old bytes as a recovery copy.")

            try store.add(name: "Alex", avatar: .ocean)
            let second = try XCTUnwrap(store.profiles.first { $0.id != original.id })
            store.select(second.id)
            assertEmpty(store.library)
            guest.toggleSaved(title(99, .movie))

            let restored = ProfileStore(defaults: defaults)
            XCTAssertEqual(restored.activeProfile?.id, second.id)
            assertEmpty(restored.library)
            restored.select(original.id)
            XCTAssertEqual(restored.library.saved.map(\.key), [movie.key], "A later launch must not reimport changes from the old guest store.")
            XCTAssertEqual(restored.library.history.first?.positionSeconds, 125)
        }
    }

    @MainActor
    func testSwitchingIsolatesSavedHistoryTeamsSearchesAndGenres() throws {
        try withDefaults { defaults in
            let store = ProfileStore(defaults: defaults, chooseOnLaunch: false)
            let original = try XCTUnwrap(store.activeProfile)
            let movie = title(42, .movie), show = title(42, .tv)
            store.library.toggleSaved(movie)
            store.library.record(show, season: 2, episode: 4, positionSeconds: 600, durationSeconds: 2400)
            store.library.toggleTeam("nba:13")
            store.library.rememberSearch("Horizon")
            store.library.setGenre(18)

            try store.add(name: "Jordan", avatar: .forest)
            let second = try XCTUnwrap(store.profiles.first { $0.id != original.id })
            store.select(second.id)
            assertEmpty(store.library)
            store.library.toggleSaved(show)
            store.library.record(movie, positionSeconds: 35, durationSeconds: 900)
            store.library.toggleTeam("nfl:2")
            store.library.rememberSearch("Middle-earth")
            store.library.setGenre(12)

            store.select(original.id)
            XCTAssertEqual(store.library.saved.map(\.key), ["movie:42"])
            XCTAssertEqual(store.library.history.map { $0.media.key }, ["tv:42"])
            XCTAssertEqual(store.library.history.first?.season, 2)
            XCTAssertEqual(store.library.history.first?.episode, 4)
            XCTAssertEqual(store.library.history.first?.positionSeconds, 600)
            XCTAssertEqual(store.library.followedTeams, ["nba:13"])
            XCTAssertEqual(store.library.recentSearches, ["Horizon"])
            XCTAssertEqual(store.library.favoriteGenres, [18])

            store.select(second.id)
            XCTAssertEqual(store.library.saved.map(\.key), ["tv:42"])
            XCTAssertEqual(store.library.history.map { $0.media.key }, ["movie:42"])
            XCTAssertEqual(store.library.history.first?.positionSeconds, 35)
            XCTAssertEqual(store.library.followedTeams, ["nfl:2"])
            XCTAssertEqual(store.library.recentSearches, ["Middle-earth"])
            XCTAssertEqual(store.library.favoriteGenres, [12])
        }
    }

    @MainActor
    func testLatePlaybackCheckpointWritesToTheProfileThatStartedPlayback() throws {
        try withDefaults { defaults in
            let store = ProfileStore(defaults: defaults, chooseOnLaunch: false)
            let original = try XCTUnwrap(store.activeProfile)
            let oldLibrary = store.library
            try store.add(name: "Second", avatar: .violet)
            let second = try XCTUnwrap(store.profiles.first { $0.id != original.id })
            store.select(second.id)
            XCTAssertFalse(oldLibrary === store.library)

            oldLibrary.record(title(42, .tv), season: 1, episode: 3, positionSeconds: 713, durationSeconds: 2700)
            XCTAssertTrue(store.library.history.isEmpty, "An old player's callback cannot leak into the currently selected profile.")
            store.select(original.id)
            XCTAssertEqual(store.library.history.first?.episode, 3)
            XCTAssertEqual(store.library.history.first?.positionSeconds, 713)
            store.select(second.id)
            XCTAssertTrue(store.library.history.isEmpty)
        }
    }

    @MainActor
    func testDeletingInactiveProfileInvalidatesItsRetainedLibraryAndCannotRecreateStorage() throws {
        try withDefaults { defaults in
            let store = ProfileStore(defaults: defaults, chooseOnLaunch: false)
            let original = try XCTUnwrap(store.activeProfile)
            let retainedLibrary = store.library
            retainedLibrary.toggleSaved(title(42, .movie))
            try store.add(name: "Keep me", avatar: .gold)
            let remaining = try XCTUnwrap(store.profiles.first { $0.id != original.id })
            store.select(remaining.id)
            store.library.toggleSaved(title(99, .movie))
            try store.remove(original.id)

            retainedLibrary.record(title(42, .movie), positionSeconds: 850, durationSeconds: 1800)
            retainedLibrary.toggleTeam("nba:13")
            XCTAssertNil(defaults.data(forKey: libraryKey(original.id)), "A deleted profile's delayed callback must not recreate its storage.")
            XCTAssertEqual(store.profiles.map(\.id), [remaining.id])
            XCTAssertEqual(store.library.saved.map(\.key), ["movie:99"])
            XCTAssertTrue(store.library.history.isEmpty)
        }
    }

    @MainActor
    func testDeletingActiveProfileChoosesRemainingLibraryAndRejectsItsLateWrites() throws {
        try withDefaults { defaults in
            let store = ProfileStore(defaults: defaults, chooseOnLaunch: false)
            let original = try XCTUnwrap(store.activeProfile)
            let retainedLibrary = store.library
            try store.add(name: "Remaining", avatar: .slate)
            let remaining = try XCTUnwrap(store.profiles.first { $0.id != original.id })
            try store.remove(original.id)
            retainedLibrary.record(title(42, .movie), positionSeconds: 90, durationSeconds: 900)
            XCTAssertNil(defaults.data(forKey: libraryKey(original.id)))
            XCTAssertEqual(store.activeProfile?.id, remaining.id)
            XCTAssertTrue(store.requiresSelection)
            assertEmpty(store.library)
            XCTAssertThrowsError(try store.remove(remaining.id))
            XCTAssertEqual(store.profiles.map(\.id), [remaining.id])
        }
    }

    @MainActor
    func testColdLaunchRequiresChooserWhileRememberingLastProfileAndItsLibrary() throws {
        try withDefaults { defaults in
            let first = ProfileStore(defaults: defaults)
            XCTAssertTrue(first.requiresSelection)
            try first.add(name: "Last selected", avatar: .ocean)
            let selected = try XCTUnwrap(first.profiles.last)
            first.select(selected.id)
            first.library.toggleSaved(title(99, .movie))
            XCTAssertFalse(first.requiresSelection)

            let relaunched = ProfileStore(defaults: defaults)
            XCTAssertTrue(relaunched.requiresSelection)
            XCTAssertEqual(relaunched.activeProfile?.id, selected.id)
            XCTAssertEqual(relaunched.library.saved.map(\.key), ["movie:99"])
            relaunched.select(UUID())
            XCTAssertTrue(relaunched.requiresSelection, "An invalid profile identity cannot bypass the chooser.")
            relaunched.select(selected.id)
            XCTAssertFalse(relaunched.requiresSelection)
            relaunched.showChooser()
            XCTAssertTrue(relaunched.requiresSelection)
            relaunched.cancelSwitch()
            XCTAssertFalse(relaunched.requiresSelection)
            XCTAssertEqual(relaunched.activeProfile?.id, selected.id)
        }
    }

    @MainActor
    func testAddEditLimitsAndNameValidationPreserveExistingProfilesOnFailure() throws {
        try withDefaults { defaults in
            let store = ProfileStore(defaults: defaults, chooseOnLaunch: false)
            let first = try XCTUnwrap(store.activeProfile)
            for invalid in ["", "   ", "Jo\nsh", String(repeating: "x", count: 25)] {
                XCTAssertThrowsError(try store.add(name: invalid, avatar: .ocean))
                XCTAssertThrowsError(try store.update(id: first.id, name: invalid, avatar: .ocean))
            }
            XCTAssertEqual(store.profiles.count, 1)
            XCTAssertEqual(store.activeProfile, first)
            try store.update(id: first.id, name: "  Zoë 🌲  ", avatar: .forest)
            XCTAssertEqual(store.activeProfile?.name, "Zoë 🌲")
            XCTAssertEqual(store.activeProfile?.avatar, .forest)
            for index in 2...5 { try store.add(name: String(repeating: "x", count: 23) + String(index), avatar: .ocean) }
            XCTAssertEqual(store.profiles.count, 5)
            XCTAssertEqual(Set(store.profiles.map(\.id)).count, 5)
            XCTAssertThrowsError(try store.add(name: "Sixth", avatar: .gold))
            XCTAssertThrowsError(try store.update(id: UUID(), name: "Missing", avatar: .slate))
            XCTAssertThrowsError(try store.remove(UUID()))
            XCTAssertEqual(store.profiles.count, 5)
            let restored = ProfileStore(defaults: defaults)
            XCTAssertEqual(restored.profiles, store.profiles)
        }
    }

    private func title(_ id: Int, _ kind: MediaKind) -> MediaItem { MediaItem(id: id, kind: kind, title: "Fixture \(kind.rawValue) \(id)") }
    private func libraryKey(_ id: UUID) -> String { "streamify.ios.profileLibrary.\(id.uuidString).v1" }

    @MainActor private func assertEmpty(_ library: LibraryStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(library.saved.isEmpty, file: file, line: line)
        XCTAssertTrue(library.history.isEmpty, file: file, line: line)
        XCTAssertTrue(library.recentSearches.isEmpty, file: file, line: line)
        XCTAssertTrue(library.followedTeams.isEmpty, file: file, line: line)
        XCTAssertTrue(library.favoriteGenres.isEmpty, file: file, line: line)
    }

    @MainActor private func withDefaults(_ action: (UserDefaults) throws -> Void) throws {
        let suite = "streamify-profile-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try action(defaults)
    }
}
