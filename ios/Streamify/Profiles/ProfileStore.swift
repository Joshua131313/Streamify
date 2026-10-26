import Foundation
import Combine

enum ProfileAvatar: String, Codable, CaseIterable, Identifiable, Sendable {
    case crimson, ocean, forest, violet, gold, slate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crimson: return "Crimson"
        case .ocean: return "Dragon"
        case .forest: return "Panda"
        case .violet: return "Astronaut"
        case .gold: return "Fox"
        case .slate: return "Robot"
        }
    }
    var artworkName: String { "profile-avatar-\(rawValue)" }
}

struct AppProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var avatar: ProfileAvatar
}

enum ProfileSyncStatus: Equatable {
    case local, loading, syncing, synced, pending, failed(String), conflict
    var title: String {
        switch self {
        case .local: "Saved on this iPhone"
        case .loading: "Loading account profiles…"
        case .syncing: "Syncing profile preferences…"
        case .synced: "Profile preferences synced"
        case .pending: "Changes saved on this iPhone · sync pending"
        case .failed(let message): message
        case .conflict: ProfileSyncError.conflict.localizedDescription
        }
    }
}

/// Every account/profile pair owns separate stores. Late playback checkpoints
/// keep writing to their original owner; signing out restores the untouched guest.
@MainActor final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [AppProfile]
    @Published private(set) var activeProfile: AppProfile?
    @Published private(set) var library: LibraryStore
    @Published private(set) var settings: SettingsStore
    @Published private(set) var requiresSelection: Bool
    @Published private(set) var ownerUID: String?
    @Published private(set) var syncStatus: ProfileSyncStatus = .local
    var contextID: String { "\(ownerUID ?? "guest"):\(activeProfile?.id.uuidString ?? "none")" }
    var canEditProfiles: Bool { ownerUID == nil || journal.baselineRevision != nil }
    private let defaults: UserDefaults
    private let backend: any ProfileSyncBackend
    private var libraries: [UUID: LibraryStore] = [:]
    private var preferences: [UUID: SettingsStore] = [:]
    private var session = UUID()
    private var retryTask: Task<Void, Never>?
    private var syncing = false
    private var applyingCloud = false
    private var journal = Journal()
    private static let key = "streamify.ios.profiles.v1"
    private static let migrationKey = "streamify.ios.profiles.guestLibraryMigrated.v1"
    private struct Snapshot: Codable { var profiles: [AppProfile]; var selectedID: UUID? }
    private struct Journal: Codable {
        var baselineRevision: Int?
        var pending: ProfileCloudPayload?
        var inFlight: ProfileCloudPayload?
        var inFlightRevision: Int?
        var initialImport: ProfileCloudPayload?
    }

    init(defaults: UserDefaults = .standard, chooseOnLaunch: Bool = true, backend: (any ProfileSyncBackend)? = nil) {
        self.defaults = defaults
        self.backend = backend ?? FirebaseProfileSyncBackend()
        let snapshot = Self.restore(defaults: defaults, owner: nil)
        profiles = snapshot.profiles
        let selected = snapshot.profiles.first { $0.id == snapshot.selectedID } ?? snapshot.profiles[0]
        activeProfile = selected
        requiresSelection = chooseOnLaunch
        if !defaults.bool(forKey: Self.migrationKey) {
            let destination = Self.libraryKey(snapshot.profiles[0].id, owner: nil)
            if defaults.data(forKey: destination) == nil, let legacy = defaults.data(forKey: "streamify.ios.guestLibrary.v1") {
                defaults.set(legacy, forKey: destination)
            }
            defaults.set(true, forKey: Self.migrationKey)
        }
        // Only the original guest inherits the former device-wide preferences.
        let firstID = snapshot.profiles[0].id
        let preferenceMigrationKey = "streamify.ios.profiles.preferencesMigrated.v1"
        let firstSettings = SettingsStore(defaults: defaults, profileKey: Self.preferenceKey(firstID, owner: nil), migrateLegacy: !defaults.bool(forKey: preferenceMigrationKey))
        defaults.set(true, forKey: preferenceMigrationKey)
        settings = selected.id == firstID ? firstSettings : SettingsStore(defaults: defaults, profileKey: Self.preferenceKey(selected.id, owner: nil))
        library = LibraryStore(defaults: defaults, storageKey: Self.libraryKey(selected.id, owner: nil))
        libraries[selected.id] = library
        preferences[firstID] = firstSettings
        preferences[selected.id] = settings
        bindStores(id: selected.id)
        persist()
    }
    deinit { retryTask?.cancel() }

    func select(_ id: UUID) {
        guard canEditProfiles else { return }
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activate(profile)
        settings.refreshDeviceConfiguration()
        persist()
        requiresSelection = false
    }
    func showChooser() { requiresSelection = true }
    func cancelSwitch() { if activeProfile != nil { requiresSelection = false } }
    /// Enter the account's own last-used profile only after its load has settled.
    func finishSignIn(uid: String) -> Bool {
        guard ownerUID == uid, canEditProfiles, let selected = activeProfile else { return false }
        if syncStatus == .loading || syncStatus == .syncing { return false }
        select(selected.id)
        return !requiresSelection
    }
    func add(name: String, avatar: ProfileAvatar) throws {
        guard canEditProfiles else { throw ProfileSyncError.notReady }
        guard profiles.count < 5 else { throw ProfileError.limit }
        profiles.append(AppProfile(id: UUID(), name: try validName(name), avatar: avatar))
        changed()
    }
    func update(id: UUID, name: String, avatar: ProfileAvatar) throws {
        guard canEditProfiles else { throw ProfileSyncError.notReady }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        profiles[index].name = try validName(name)
        profiles[index].avatar = avatar
        if activeProfile?.id == id { activeProfile = profiles[index] }
        changed()
    }
    func remove(_ id: UUID) throws {
        guard canEditProfiles else { throw ProfileSyncError.notReady }
        guard profiles.count > 1 else { throw ProfileError.last }
        guard profiles.contains(where: { $0.id == id }) else { throw ProfileError.missing }
        if let removed = libraries.removeValue(forKey: id) { removed.discardStorage() }
        else { defaults.removeObject(forKey: Self.libraryKey(id, owner: ownerUID)) }
        if let removed = preferences.removeValue(forKey: id) { removed.discardProfilePreferences() }
        else { defaults.removeObject(forKey: Self.preferenceKey(id, owner: ownerUID)) }
        profiles.removeAll { $0.id == id }
        if activeProfile?.id == id { activate(profiles[0]); requiresSelection = true }
        changed()
    }

    func setAccount(_ identity: AccountIdentity?) async {
        let next = identity.flatMap { $0.isValid ? $0.uid : nil }
        guard next != ownerUID else { return }
        persist()
        retryTask?.cancel()
        session = UUID(); syncing = false
        ownerUID = next
        libraries.removeAll(); preferences.removeAll()
        journal = next.flatMap { defaults.data(forKey: Self.journalKey($0)) }.flatMap { try? JSONDecoder().decode(Journal.self, from: $0) } ?? Journal()
        let snapshot = Self.restore(defaults: defaults, owner: next)
        profiles = snapshot.profiles
        activate(profiles.first { $0.id == snapshot.selectedID } ?? profiles[0])
        requiresSelection = true
        syncStatus = next == nil ? .local : .loading
        persist()
        if next != nil { await retrySync() }
    }

    func retrySync() async {
        guard let uid = ownerUID, !syncing else { return }
        let expectedSession = session
        syncing = true
        syncStatus = journal.baselineRevision == nil ? .loading : .syncing
        defer { if session == expectedSession { syncing = false } }
        do {
            let remote = try await backend.load(uid: uid)
            try guardSession(expectedSession)
            if journal.baselineRevision == nil {
                if let remote {
                    if remote.payload == journal.initialImport { importGuestLibraries(remote.payload, uid: uid) }
                    try apply(remote)
                }
                else {
                    let candidate = journal.initialImport ?? payload(for: nil)
                    journal.initialImport = candidate
                    persistJournal()
                    let created = try await backend.createIfAbsent(uid: uid, payload: candidate)
                    try guardSession(expectedSession)
                    if created.createdNew || created.payload == journal.initialImport { importGuestLibraries(candidate, uid: uid) }
                    try apply(created)
                }
            } else if let pending = journal.pending {
                guard let remote else { throw ProfileSyncError.conflict }
                if remote.payload == pending {
                    journal.baselineRevision = remote.revision
                    journal.pending = nil
                    journal.inFlight = nil; journal.inFlightRevision = nil
                    persistJournal()
                } else {
                    // A timed-out earlier write may have committed while a newer
                    // local edit was queued. Recognize that exact write, then send
                    // the newer edit instead of reporting a false device conflict.
                    if let revision = journal.inFlightRevision, revision < Int.max,
                       remote.revision == revision + 1, remote.payload == journal.inFlight {
                        journal.baselineRevision = remote.revision
                        journal.inFlight = nil; journal.inFlightRevision = nil
                        persistJournal()
                    }
                    guard remote.revision == journal.baselineRevision else { throw ProfileSyncError.conflict }
                    journal.inFlight = pending; journal.inFlightRevision = remote.revision
                    persistJournal()
                    let committed = try await backend.commit(uid: uid, expectedRevision: remote.revision, payload: pending)
                    try guardSession(expectedSession)
                    journal.baselineRevision = committed.revision
                    journal.inFlight = nil; journal.inFlightRevision = nil
                    // Changes made while the write was in flight form the next durable write.
                    if journal.pending == pending { journal.pending = nil }
                    persistJournal()
                }
            } else {
                guard let remote else { throw ProfileSyncError.conflict }
                try apply(remote)
            }
            syncStatus = journal.pending == nil ? .synced : .pending
            if journal.pending != nil { scheduleRetry(after: 0.4) }
        } catch is CancellationError {
            if session == expectedSession { syncStatus = .pending; scheduleRetry(after: 2) }
        } catch {
            guard session == expectedSession else { return }
            if error.localizedDescription == ProfileSyncError.conflict.localizedDescription { syncStatus = .conflict }
            else { syncStatus = .failed(error.localizedDescription); scheduleRetry(after: 25) }
        }
    }

    /// Explicit conflict resolution; never discard a pending local edit automatically.
    func reloadCloudProfiles() async {
        guard let uid = ownerUID, !syncing else { return }
        let expectedSession = session
        syncing = true; syncStatus = .loading
        defer { if session == expectedSession { syncing = false } }
        do {
            guard let remote = try await backend.load(uid: uid) else { throw ProfileSyncError.conflict }
            try guardSession(expectedSession)
            // Preserve a recovery copy before an explicit reload replaces pending preferences.
            if let pending = journal.pending, let data = try? JSONEncoder().encode(pending) {
                defaults.set(data, forKey: Self.journalKey(uid) + ".recovery")
            }
            try apply(remote)
            syncStatus = .synced
        } catch is CancellationError {
            if session == expectedSession { syncStatus = .pending }
        } catch { if session == expectedSession { syncStatus = .failed(error.localizedDescription) } }
    }

    private func apply(_ document: ProfileCloudDocument) throws {
        let payload = try document.payload.validated()
        guard document.revision > 0 else { throw ProfileSyncError.invalidData }
        applyingCloud = true
        defer { applyingCloud = false }
        let previous = activeProfile?.id
        profiles = payload.profiles.map(\.profile)
        for entry in payload.profiles {
            let id = entry.profile.id
            let library = libraryFor(id)
            let settings = settingsFor(id)
            library.applyPreferences(genres: entry.favoriteGenres, teams: entry.followedTeams)
            settings.applyPreferences(appearance: entry.appearance, serverID: entry.serverID)
        }
        activate(profiles.first { $0.id == previous } ?? profiles[0])
        journal.baselineRevision = document.revision
        journal.pending = nil
        journal.inFlight = nil; journal.inFlightRevision = nil; journal.initialImport = nil
        persist(); persistJournal()
    }
    private func guardSession(_ expected: UUID) throws {
        try Task.checkCancellation()
        guard session == expected else { throw CancellationError() }
    }
    private func importGuestLibraries(_ payload: ProfileCloudPayload, uid: String) {
        // Exact imported UUIDs distinguish our timed-out create from an unrelated
        // existing cloud profile set. Never overwrite a library already used here.
        for entry in payload.profiles {
            let destination = Self.libraryKey(entry.profile.id, owner: uid)
            if defaults.data(forKey: destination) == nil,
               let data = defaults.data(forKey: Self.libraryKey(entry.profile.id, owner: nil)) {
                defaults.set(data, forKey: destination)
            }
        }
    }
    private func changed() {
        persist()
        guard !applyingCloud, ownerUID != nil, canEditProfiles else { return }
        journal.pending = payload(for: ownerUID)
        persistJournal()
        syncStatus = .pending
        scheduleRetry(after: 0.4)
    }
    private func scheduleRetry(after seconds: Double) {
        retryTask?.cancel()
        let expectedSession = session
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.session == expectedSession else { return }
            self.retryTask = nil
            await self.retrySync()
        }
    }
    private func activate(_ profile: AppProfile) {
        activeProfile = profile
        library = libraryFor(profile.id)
        settings = settingsFor(profile.id)
        bindStores(id: profile.id)
    }
    private func libraryFor(_ id: UUID) -> LibraryStore {
        if let store = libraries[id] { return store }
        let store = LibraryStore(defaults: defaults, storageKey: Self.libraryKey(id, owner: ownerUID))
        libraries[id] = store
        bindStores(id: id)
        return store
    }
    private func settingsFor(_ id: UUID) -> SettingsStore {
        if let store = preferences[id] { return store }
        let store = SettingsStore(defaults: defaults, profileKey: Self.preferenceKey(id, owner: ownerUID))
        preferences[id] = store
        bindStores(id: id)
        return store
    }
    private func bindStores(id: UUID) {
        let owner = ownerUID
        let callback: () -> Void = { [weak self] in
            guard let self, self.ownerUID == owner, self.profiles.contains(where: { $0.id == id }) else { return }
            self.changed()
        }
        libraries[id]?.onPreferencesChange = callback
        preferences[id]?.onPreferencesChange = callback
    }
    private func payload(for owner: String?) -> ProfileCloudPayload {
        let values = owner == ownerUID ? profiles : Self.restore(defaults: defaults, owner: owner).profiles
        return ProfileCloudPayload(profiles: values.map { profile in
            let library = owner == ownerUID ? libraryFor(profile.id) : LibraryStore(defaults: defaults, storageKey: Self.libraryKey(profile.id, owner: owner))
            let settings = owner == ownerUID ? settingsFor(profile.id) : SettingsStore(defaults: defaults, profileKey: Self.preferenceKey(profile.id, owner: owner))
            return ProfileCloudEntry(profile: profile, appearance: settings.appearance, serverID: settings.serverID,
                favoriteGenres: library.favoriteGenres, followedTeams: library.followedTeams)
        })
    }
    private static func restore(defaults: UserDefaults, owner: String?) -> Snapshot {
        let decoded = defaults.data(forKey: snapshotKey(owner)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        var seen = Set<UUID>()
        let valid = decoded?.profiles.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted } ?? []
        let values = Array(valid.prefix(5))
        return Snapshot(profiles: values.isEmpty ? [AppProfile(id: UUID(), name: "My profile", avatar: .crimson)] : values, selectedID: decoded?.selectedID)
    }
    private func validName(_ value: String) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 24, !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ProfileError.name }
        return clean
    }
    private static func ownerSuffix(_ owner: String) -> String { Data(owner.utf8).map { String(format: "%02x", $0) }.joined() }
    private static func snapshotKey(_ owner: String?) -> String { owner.map { "streamify.ios.account.\(ownerSuffix($0)).profiles.v1" } ?? key }
    private static func journalKey(_ owner: String) -> String { "streamify.ios.account.\(ownerSuffix(owner)).sync.v1" }
    private static func libraryKey(_ id: UUID, owner: String?) -> String {
        owner.map { "streamify.ios.account.\(ownerSuffix($0)).library.\(id.uuidString).v1" } ?? "streamify.ios.profileLibrary.\(id.uuidString).v1"
    }
    private static func preferenceKey(_ id: UUID, owner: String?) -> String {
        owner.map { "streamify.ios.account.\(ownerSuffix($0)).preferences.\(id.uuidString).v1" } ?? "streamify.ios.profilePreferences.\(id.uuidString).v1"
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(Snapshot(profiles: profiles, selectedID: activeProfile?.id)) { defaults.set(data, forKey: Self.snapshotKey(ownerUID)) }
    }
    private func persistJournal() {
        guard let uid = ownerUID, let data = try? JSONEncoder().encode(journal) else { return }
        defaults.set(data, forKey: Self.journalKey(uid))
    }
    private enum ProfileError: LocalizedError {
        case limit, last, missing, name
        var errorDescription: String? {
            switch self {
            case .limit: "You can have up to five profiles."
            case .last: "Keep at least one profile on this iPhone."
            case .missing: "This profile is no longer available."
            case .name: "Use a profile name between 1 and 24 characters."
            }
        }
    }
}
