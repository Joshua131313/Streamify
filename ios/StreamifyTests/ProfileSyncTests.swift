import Foundation
import XCTest
@testable import Streamify

@MainActor final class ProfileSyncTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ProfileSyncTests.\(UUID().uuidString)")!
    }
    private func cloud(_ name: String, id: UUID = UUID(), revision: Int = 1) -> ProfileCloudDocument {
        ProfileCloudDocument(revision: revision, payload: ProfileCloudPayload(profiles: [ProfileCloudEntry(
            profile: AppProfile(id: id, name: name, avatar: .forest), appearance: "Light", serverID: "vidy",
            favoriteGenres: [18], followedTeams: ["nba:2"])]))
    }
    func testExplicitSignInWaitsForAccountAndUsesItsLastSelectedProfile() async throws {
        let backend = ProfileBackendFake(), defaults = defaults()
        let first = cloud("First"), second = cloud("Second")
        backend.documents["alice"] = ProfileCloudDocument(revision: 1,
            payload: ProfileCloudPayload(profiles: first.payload.profiles + second.payload.profiles))
        let store = ProfileStore(defaults: defaults, backend: backend)
        XCTAssertFalse(store.finishSignIn(uid: "alice"))
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        XCTAssertTrue(store.requiresSelection, "Restored accounts must still choose a profile on a normal launch.")
        store.select(second.payload.profiles[0].profile.id)
        await store.setAccount(nil)
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        XCTAssertTrue(store.requiresSelection)
        XCTAssertFalse(store.finishSignIn(uid: "other-account"))
        XCTAssertTrue(store.finishSignIn(uid: "alice"))
        XCTAssertEqual(store.activeProfile?.name, "Second")
        XCTAssertFalse(store.requiresSelection)
        let coldLaunch = ProfileStore(defaults: defaults, backend: backend)
        await coldLaunch.setAccount(AccountIdentity(uid: "alice", email: nil))
        XCTAssertTrue(coldLaunch.requiresSelection)
        XCTAssertEqual(coldLaunch.activeProfile?.name, "Second")
    }
    func testPreferencesAreScopedAndDeviceConnectionRemainsShared() throws {
        let defaults = defaults()
        defaults.set("Light", forKey: "streamify.ios.appearance")
        let store = ProfileStore(defaults: defaults)
        let original = try XCTUnwrap(store.activeProfile)
        XCTAssertEqual(store.settings.appearance, "Light")
        store.settings.serverID = "other"
        try store.add(name: "Alex", avatar: .gold)
        let second = store.profiles[1]
        store.select(second.id)
        XCTAssertEqual(store.settings.appearance, "Dark")
        XCTAssertEqual(store.settings.serverID, "vidy")
        store.settings.apiBase = "https://example.com"
        store.select(original.id)
        XCTAssertEqual(store.settings.appearance, "Light")
        XCTAssertEqual(store.settings.serverID, "other")
        XCTAssertEqual(store.settings.apiBase, "https://example.com")
        let relaunched = ProfileStore(defaults: defaults)
        XCTAssertEqual(relaunched.settings.appearance, "Light")
        relaunched.select(second.id)
        XCTAssertEqual(relaunched.settings.appearance, "Dark")
    }

    func testExistingCloudWinsAndGuestAndOtherAccountStayIsolated() async throws {
        let backend = ProfileBackendFake()
        let sharedID = UUID()
        backend.documents["alice"] = cloud("Alice", id: sharedID)
        backend.documents["bob"] = cloud("Bob", id: sharedID)
        let store = ProfileStore(defaults: defaults(), backend: backend)
        let guestID = try XCTUnwrap(store.activeProfile?.id)
        store.library.rememberSearch("guest only")
        store.library.toggleTeam("nfl:1")
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        XCTAssertEqual(store.activeProfile?.name, "Alice")
        XCTAssertEqual(store.library.followedTeams, ["nba:2"])
        XCTAssertTrue(store.library.recentSearches.isEmpty)
        store.library.rememberSearch("alice only")
        let aliceContext = store.contextID
        await store.setAccount(AccountIdentity(uid: "bob", email: nil))
        XCTAssertEqual(store.activeProfile?.name, "Bob")
        XCTAssertNotEqual(store.contextID, aliceContext)
        XCTAssertTrue(store.library.recentSearches.isEmpty)
        await store.setAccount(nil)
        XCTAssertEqual(store.activeProfile?.id, guestID)
        XCTAssertEqual(store.library.recentSearches, ["guest only"])
        XCTAssertEqual(store.library.followedTeams, ["nfl:1"])
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        XCTAssertEqual(store.library.recentSearches, ["alice only"])
        XCTAssertEqual(backend.creates, 0)
    }

    func testFirstAccountCopiesGuestPreferencesAndLocalLibraryWithoutRemovingGuest() async throws {
        let backend = ProfileBackendFake()
        let store = ProfileStore(defaults: defaults(), backend: backend)
        let guestID = try XCTUnwrap(store.activeProfile?.id)
        store.library.rememberSearch("retained guest")
        store.library.setGenre(35)
        store.library.toggleTeam("nfl:1")
        store.settings.appearance = "Light"
        store.settings.apiBase = "https://device-only.example"
        await store.setAccount(AccountIdentity(uid: "first", email: "a@example.com"))
        XCTAssertEqual(store.activeProfile?.id, guestID)
        XCTAssertEqual(store.library.recentSearches, ["retained guest"])
        XCTAssertEqual(store.library.followedTeams, ["nfl:1"])
        XCTAssertEqual(store.settings.appearance, "Light")
        let payload = try XCTUnwrap(backend.documents["first"]?.payload)
        let serialized = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        XCTAssertFalse(serialized.contains("apiBase"))
        XCTAssertFalse(serialized.contains("tmdbToken"))
        XCTAssertFalse(serialized.contains("recentSearches"))
        XCTAssertFalse(serialized.contains("device-only"))
        store.library.clearSearches()
        await store.setAccount(nil)
        XCTAssertEqual(store.library.recentSearches, ["retained guest"])
    }

    func testCreatedProfilesAndFailedWritesSurviveRelaunchThenCommit() async throws {
        let defaults = defaults(), backend = ProfileBackendFake()
        backend.documents["alice"] = cloud("Alice")
        var store = ProfileStore(defaults: defaults, backend: backend)
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        try store.add(name: "New profile", avatar: .violet)
        backend.commitError = ProfileSyncError.timeout
        await store.retrySync()
        if case .failed = store.syncStatus {} else { XCTFail("A failed write must not be marked synced") }
        let secondID = store.profiles[1].id
        await store.setAccount(nil)
        store = ProfileStore(defaults: defaults, backend: backend)
        backend.loadError = ProfileSyncError.timeout
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertTrue(store.canEditProfiles)
        XCTAssertTrue(store.profiles.contains { $0.id == secondID })
        backend.loadError = nil; backend.commitError = nil
        await store.retrySync()
        XCTAssertEqual(store.syncStatus, .synced)
        XCTAssertEqual(backend.documents["alice"]?.payload.profiles.count, 2)
    }

    func testServerCommitAfterTimeoutWithNewerLocalEditReconcilesInFlightWrite() async throws {
        let backend = ProfileBackendFake()
        backend.documents["alice"] = cloud("Alice")
        let store = ProfileStore(defaults: defaults(), backend: backend)
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        store.settings.appearance = "Dark"
        backend.afterCommit = {
            store.settings.appearance = "System"
            throw ProfileSyncError.timeout
        }
        await store.retrySync()
        XCTAssertEqual(backend.documents["alice"]?.payload.profiles[0].appearance, "Dark")
        backend.afterCommit = nil
        await store.retrySync()
        XCTAssertEqual(store.syncStatus, .synced)
        XCTAssertEqual(backend.documents["alice"]?.payload.profiles[0].appearance, "System")
    }

    func testFirstCreateTimeoutStillImportsGuestLibraryOnConfirmedRead() async throws {
        let backend = ProfileBackendFake()
        backend.createErrorAfterCommit = ProfileSyncError.timeout
        let store = ProfileStore(defaults: defaults(), backend: backend)
        store.library.rememberSearch("guest search")
        await store.setAccount(AccountIdentity(uid: "first", email: nil))
        XCTAssertFalse(store.canEditProfiles)
        backend.createErrorAfterCommit = nil
        await store.retrySync()
        XCTAssertEqual(store.syncStatus, .synced)
        XCTAssertEqual(store.library.recentSearches, ["guest search"])
    }

    func testConflictingDeviceEditDoesNotOverwriteCloudOrDiscardPendingLocal() async throws {
        let backend = ProfileBackendFake()
        let original = cloud("Alice")
        backend.documents["alice"] = original
        let store = ProfileStore(defaults: defaults(), backend: backend)
        await store.setAccount(AccountIdentity(uid: "alice", email: nil))
        try store.update(id: original.payload.profiles[0].profile.id, name: "Local", avatar: .ocean)
        backend.documents["alice"] = cloud("Other device", id: original.payload.profiles[0].profile.id, revision: 2)
        await store.retrySync()
        XCTAssertEqual(store.syncStatus, .conflict)
        XCTAssertEqual(store.activeProfile?.name, "Local")
        XCTAssertEqual(backend.documents["alice"]?.payload.profiles[0].profile.name, "Other device")
        await store.reloadCloudProfiles()
        XCTAssertEqual(store.activeProfile?.name, "Other device")
    }

    func testLateOldAccountLoadCannotChangeNewAccount() async throws {
        let backend = ProfileBackendFake()
        let alice = cloud("Alice"), bob = cloud("Bob")
        backend.documents["bob"] = bob
        var held: CheckedContinuation<ProfileCloudDocument?, Error>?
        backend.loadOverride = { uid in
            if uid == "alice" { return try await withCheckedThrowingContinuation { held = $0 } }
            return backend.documents[uid]
        }
        let store = ProfileStore(defaults: defaults(), backend: backend)
        let old = Task { await store.setAccount(AccountIdentity(uid: "alice", email: nil)) }
        for _ in 0..<100 where held == nil { await Task.yield() }
        XCTAssertNotNil(held)
        XCTAssertFalse(store.canEditProfiles)
        let placeholder = try XCTUnwrap(store.activeProfile?.id)
        store.select(placeholder)
        XCTAssertTrue(store.requiresSelection)
        await store.setAccount(AccountIdentity(uid: "bob", email: nil))
        held?.resume(returning: alice)
        await old.value
        XCTAssertEqual(store.ownerUID, "bob")
        XCTAssertEqual(store.activeProfile?.name, "Bob")
        XCTAssertEqual(store.syncStatus, .synced)
    }

    func testDeadlineReturnsWithoutWaitingForLateBackendCallback() async throws {
        var finish: ((Result<Int, Error>) -> Void)?
        do {
            let _: Int = try await withProfileDeadline(seconds: 0.01) { finish = $0 }
            XCTFail("Expected deadline")
        } catch { XCTAssertEqual(error.localizedDescription, ProfileSyncError.timeout.localizedDescription) }
        finish?(.success(1)) // A late callback must neither crash nor resume twice.
    }
}

@MainActor private final class ProfileBackendFake: ProfileSyncBackend {
    var documents: [String: ProfileCloudDocument] = [:]
    var creates = 0
    var loadError: Error?
    var commitError: Error?
    var createErrorAfterCommit: Error?
    var afterCommit: (() throws -> Void)?
    var loadOverride: ((String) async throws -> ProfileCloudDocument?)?
    func load(uid: String) async throws -> ProfileCloudDocument? {
        if let loadOverride { return try await loadOverride(uid) }
        if let loadError { throw loadError }
        return documents[uid]
    }
    func createIfAbsent(uid: String, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument {
        if let existing = documents[uid] { return existing }
        creates += 1
        let created = ProfileCloudDocument(revision: 1, payload: payload, createdNew: true)
        documents[uid] = created
        if let createErrorAfterCommit { throw createErrorAfterCommit }
        return created
    }
    func commit(uid: String, expectedRevision: Int, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument {
        if let commitError { throw commitError }
        guard documents[uid]?.revision == expectedRevision else { throw ProfileSyncError.conflict }
        let result = ProfileCloudDocument(revision: expectedRevision + 1, payload: payload)
        documents[uid] = result
        try afterCommit?()
        return result
    }
}
