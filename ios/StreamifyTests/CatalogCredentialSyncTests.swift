import XCTest
@testable import Streamify

@MainActor final class CatalogCredentialSyncTests: XCTestCase {
    private let alice = AccountIdentity(uid: "alice", email: nil)
    private let bob = AccountIdentity(uid: "bob", email: nil)

    func testSignedInUpgradeClaimsLegacyOnlyForItsInitialOwner() async throws {
        let storage = MemoryCatalogCredentials(values: ["tmdbToken": "legacy-key"])
        let backend = TestCatalogCredentialBackend()
        let sync = coordinator(backend: backend, storage: storage)
        sync.connect(alice)
        await waitUntil { sync.state.key == "legacy-key" }
        XCTAssertEqual(backend.documents[alice.uid], "legacy-key")
        XCTAssertEqual(backend.imports, [alice.uid])

        sync.connect(bob)
        await waitUntil { backend.subscribedUID == self.bob.uid }
        XCTAssertEqual(sync.state.key, "")
        XCTAssertNil(backend.documents[bob.uid])
        XCTAssertThrowsError(try sync.save("alice-secret", owner: alice.uid))
        sync.connect(nil)
        XCTAssertEqual(sync.state.key, "legacy-key")
    }

    func testGuestUpgradeRequiresAnExplicitSaveAfterSignIn() async throws {
        let storage = MemoryCatalogCredentials(values: ["tmdbToken": "guest-key"])
        let backend = TestCatalogCredentialBackend()
        let sync = coordinator(backend: backend, storage: storage)
        sync.connect(nil)
        sync.connect(alice)
        await waitUntil { backend.subscribedUID == self.alice.uid }
        XCTAssertEqual(sync.state.key, "")
        XCTAssertNil(backend.documents[alice.uid])

        try sync.save("  account-key \n", owner: alice.uid)
        await waitUntil { backend.documents[self.alice.uid] == "account-key" }
        sync.connect(nil)
        XCTAssertEqual(sync.state.key, "guest-key")
    }

    func testAuthoritativeEmptyDoesNotResurrectLegacyAndSharedSettingsUpdate() async throws {
        let storage = MemoryCatalogCredentials(values: ["tmdbToken": "legacy-key"])
        let backend = TestCatalogCredentialBackend()
        backend.documents[alice.uid] = ""
        let sync = coordinator(backend: backend, storage: storage, packagedDefault: "bundled-key")
        let first = SettingsStore(profileKey: UUID().uuidString, ownerUID: alice.uid, catalogCredential: sync)
        let second = SettingsStore(profileKey: UUID().uuidString, ownerUID: alice.uid, catalogCredential: sync)
        sync.connect(alice)
        await waitUntil { backend.subscribedUID == self.alice.uid }
        XCTAssertTrue(backend.imports.isEmpty)
        XCTAssertEqual(first.catalogKey, "")
        XCTAssertEqual(second.tmdbToken, "bundled-key")

        try first.saveCatalogKey("custom-key")
        XCTAssertEqual(second.catalogKey, "custom-key")
        await waitUntil { backend.subscribedUID == self.alice.uid && backend.documents[self.alice.uid] == "custom-key" }
        backend.update("from-another-device", for: alice.uid)
        XCTAssertEqual(first.catalogKey, "from-another-device")
        XCTAssertEqual(second.catalogKey, "from-another-device")
        try first.saveCatalogKey("")
        await waitUntil { backend.documents[self.alice.uid] == "" }
        XCTAssertEqual(second.catalogKey, "")
        XCTAssertEqual(second.tmdbToken, "bundled-key")
    }

    func testOfflinePendingClearPersistsOnlyForItsOwner() async throws {
        let storage = MemoryCatalogCredentials()
        let backend = TestCatalogCredentialBackend()
        backend.documents[alice.uid] = "alice-key"
        backend.documents[bob.uid] = "bob-key"
        backend.unavailable = true
        var sync = coordinator(backend: backend, storage: storage)
        sync.connect(nil)
        sync.connect(alice)
        try sync.save("", owner: alice.uid)
        await waitUntil { sync.state.error != nil }
        sync.connect(nil)

        backend.unavailable = false
        sync = coordinator(backend: backend, storage: storage)
        sync.connect(bob)
        await waitUntil { sync.state.key == "bob-key" }
        XCTAssertEqual(backend.documents[alice.uid], "alice-key")
        sync.connect(alice)
        await waitUntil { backend.documents[self.alice.uid] == "" }
        XCTAssertEqual(sync.state.key, "")
        XCTAssertEqual(backend.documents[bob.uid], "bob-key")
    }

    private func coordinator(backend: TestCatalogCredentialBackend, storage: MemoryCatalogCredentials,
                             packagedDefault: String = "") -> CatalogCredentialSync {
        CatalogCredentialSync(backend: backend, packagedDefault: packagedDefault, retrySeconds: 0.1,
            read: { storage.values[$0] }, write: { storage.values[$1] = $0 }, isAuthorized: { _ in true })
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

private final class MemoryCatalogCredentials {
    var values: [String: String]
    init(values: [String: String] = [:]) { self.values = values }
}

@MainActor private final class TestCatalogCredentialBackend: CatalogCredentialBackend {
    var documents: [String: String] = [:]
    var imports: [String] = []
    var unavailable = false
    private var subscriptions: [String: (Result<String?, Error>) -> Void] = [:]
    var subscribedUID: String? { subscriptions.keys.first }

    func load(uid: String) async throws -> String? {
        if unavailable { throw CatalogCredentialError.unavailable }
        return documents[uid]
    }

    func write(uid: String, key: String, onlyIfAbsent: Bool) async throws -> String {
        if unavailable { throw CatalogCredentialError.unavailable }
        if onlyIfAbsent {
            imports.append(uid)
            if let existing = documents[uid] { return existing }
        }
        documents[uid] = key
        return key
    }

    func listen(uid: String, receive: @escaping (Result<String?, Error>) -> Void) -> () -> Void {
        subscriptions[uid] = receive
        return { [weak self] in self?.subscriptions.removeValue(forKey: uid) }
    }

    func update(_ key: String?, for uid: String) {
        documents[uid] = key
        subscriptions[uid]?(.success(key))
    }
}
