import Foundation
import Combine
import Security
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Isolated per-account/profile library, with optional account cloud replication.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var saved: [MediaItem] = []
    @Published private(set) var history: [WatchEntry] = []
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var followedTeams: [String] = []
    @Published var favoriteGenres: [Int] = [] { didSet { persist(); preferencesChanged() } }
    var onPreferencesChange: (() -> Void)?
    fileprivate var onLibraryChange: (() -> Void)?
    @Published fileprivate(set) var cloudSyncMessage: String?
    @Published var historySyncMessage: String?
    private(set) var historySyncJournal = HistorySyncJournal()
    var onHistoryChange: (() -> Void)?
    private var cloudSync: LibraryCloudSync?
    private var historyCloudSync: HistoryCloudSync?
    private var applyingHistoryCloud = false
    func connectCloud(uid: String, profileID: UUID, firstProfileID: UUID) {
        guard historyCloudSync == nil, storageEnabled, FirebaseApp.app() != nil,
              Auth.auth().currentUser?.uid == uid, Auth.auth().currentUser?.isAnonymous == false else { return }
        historySyncMessage = "Syncing history and playback progress…"
        historyCloudSync = HistoryCloudSync(library: self, uid: uid, profileID: profileID, firstProfileID: firstProfileID,
            backend: FirebaseHistorySyncBackend(), identityValid: {
                Auth.auth().currentUser?.uid == uid && Auth.auth().currentUser?.isAnonymous == false
            })
    }
    func disconnectCloud() {
        cloudSync?.stop(); cloudSync = nil; cloudSyncMessage = nil
        historyCloudSync?.stop(); historyCloudSync = nil; historySyncMessage = nil
    }
    func updateHistoryJournal(_ update: (inout HistorySyncJournal) -> Void) {
        guard storageEnabled else { return }
        update(&historySyncJournal)
        applyingHistoryCloud = true
        history = historySyncJournal.visibleEntries()
        persist()
        applyingHistoryCloud = false
    }
    fileprivate func applyCloudLibrary(saved: [MediaItem], searches: [String]) {
        guard storageEnabled else { return }
        self.saved = saved
        self.recentSearches = Array(searches.prefix(20))
        persist()
    }
    private var applyingPreferences = false
    private let defaults: UserDefaults
    private let storageKey: String
    private var storageEnabled = true

    private struct Snapshot: Codable {
        var saved: [MediaItem]
        var history: [WatchEntry]
        var recentSearches: [String]
        var followedTeams: [String]
        var favoriteGenres: [Int]
        var historyJournal: HistorySyncJournal?
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "streamify.ios.guestLibrary.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        var storedHistoryJournal: HistorySyncJournal?
        if let data = defaults.data(forKey: storageKey), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            var seen = Set<String>()
            saved = snapshot.saved.filter { seen.insert($0.key).inserted }
            seen.removeAll()
            history = Array(snapshot.history.sorted { $0.watchedAt > $1.watchedAt }.filter { seen.insert($0.id).inserted }.prefix(200))
            recentSearches = Array(snapshot.recentSearches.prefix(20))
            followedTeams = Array(Set(snapshot.followedTeams)).sorted()
            favoriteGenres = snapshot.favoriteGenres
            storedHistoryJournal = snapshot.historyJournal
        }
        let journal = storedHistoryJournal ?? defaults.data(forKey: storageKey + ".historySync.v1").flatMap { try? JSONDecoder().decode(HistorySyncJournal.self, from: $0) }
        historySyncJournal = journal ?? HistorySyncJournal()
        historySyncJournal.captureLocal(history, now: Date().timeIntervalSince1970 * 1000, initial: journal == nil)
    }

    func isSaved(_ media: MediaItem) -> Bool { saved.contains { $0.key == media.key } }

    func toggleSaved(_ media: MediaItem) {
        if isSaved(media) { saved.removeAll { $0.key == media.key } }
        else { saved.insert(media, at: 0) }
        persist()
    }

    func record(_ media: MediaItem, season: Int = 1, episode: Int = 1,
                positionSeconds: Double? = nil, durationSeconds: Double? = nil) {
        let old = history.first { $0.id == media.key && $0.season == max(1, season) && $0.episode == max(1, episode) }
        let position = positionSeconds ?? old?.positionSeconds ?? 0
        let duration = durationSeconds ?? old?.durationSeconds ?? 0
        let previousMedia = history.first { $0.id == media.key }?.media ?? saved.first { $0.key == media.key }
        let entry = WatchEntry(media: media.preservingArtwork(from: previousMedia), season: max(1, season), episode: max(1, episode), watchedAt: Date(),
            positionSeconds: position.isFinite ? max(0, position) : 0,
            durationSeconds: duration.isFinite ? max(0, duration) : 0)
        history.removeAll { $0.id == media.key }
        history.insert(entry, at: 0)
        history = Array(history.prefix(200))
        persist(historyMetadataOnly: positionSeconds == nil && durationSeconds == nil)
    }

    func repairHistoryArtwork(_ media: MediaItem) {
        guard storageEnabled, let index = history.firstIndex(where: { $0.id == media.key }) else { return }
        let old = history[index]
        let repaired = media.preservingArtwork(from: old.media)
        guard repaired != old.media else { return }
        history[index] = WatchEntry(media: repaired, season: old.season, episode: old.episode, watchedAt: old.watchedAt,
                                   positionSeconds: old.positionSeconds, durationSeconds: old.durationSeconds)
        persist(historyMetadataOnly: true)
    }

    func removeHistory(_ entry: WatchEntry) { removeHistory(entry.media) }
    func removeHistory(_ media: MediaItem) {
        guard storageEnabled else { return }
        history.removeAll { $0.id == media.key }
        historySyncJournal.remove(["history:" + media.key], now: Date().timeIntervalSince1970 * 1000)
        persist(); onHistoryChange?()
    }
    func clearHistory() {
        guard storageEnabled else { return }
        let ids = Set(historySyncJournal.records.keys).union(history.map(HistorySyncEnvelope.documentID))
        history = []
        historySyncJournal.remove(ids, now: Date().timeIntervalSince1970 * 1000)
        persist(); onHistoryChange?()
    }

    func rememberSearch(_ value: String) {
        let clean = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        guard !clean.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
        recentSearches.insert(clean, at: 0)
        recentSearches = Array(recentSearches.prefix(20))
        persist()
    }
    func removeSearch(_ value: String) { recentSearches.removeAll { $0 == value }; persist() }
    func clearSearches() { recentSearches = []; persist() }

    func toggleTeam(_ key: String) {
        guard !key.isEmpty else { return }
        if followedTeams.contains(key) { followedTeams.removeAll { $0 == key } }
        else { followedTeams.append(key) }
        persist()
        preferencesChanged()
    }
    func applyPreferences(genres: [Int], teams: [String]) {
        applyingPreferences = true
        favoriteGenres = genres
        followedTeams = teams
        persist()
        applyingPreferences = false
    }
    private func preferencesChanged() {
        if storageEnabled && !applyingPreferences { onPreferencesChange?() }
    }
    func setGenre(_ id: Int) {
        if favoriteGenres.contains(id) { favoriteGenres.removeAll { $0 == id } }
        else if id > 0 { favoriteGenres.append(id) }
    }

    /// A deleted profile's late playback callback cannot recreate its library.
    func discardStorage() {
        disconnectCloud(); storageEnabled = false
        defaults.removeObject(forKey: storageKey); defaults.removeObject(forKey: storageKey + ".cloud.v1")
        defaults.removeObject(forKey: storageKey + ".historySync.v1")
    }

    private func persist(historyMetadataOnly: Bool = false) {
        guard storageEnabled else { return }
        let historyChanged = !applyingHistoryCloud && historySyncJournal.captureLocal(history,
            now: Date().timeIntervalSince1970 * 1000, metadataOnlyChange: historyMetadataOnly)
        let snapshot = Snapshot(saved: saved, history: history, recentSearches: recentSearches,
            followedTeams: followedTeams, favoriteGenres: favoriteGenres, historyJournal: historySyncJournal)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: storageKey) }
        if historyChanged { onHistoryChange?() }
        onLibraryChange?()
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var tmdbToken: String = "" {
        didSet {
            #if DEBUG
            if PreviewFixtures.enabled { credentialError = nil; return }
            #endif
            do { try SecureCredentialStore.set(tmdbToken, for: "tmdbToken"); credentialError = nil }
            catch { credentialError = error.localizedDescription }
        }
    }
    @Published var apiBase: String = "" { didSet { defaults.set(apiBase, forKey: "streamify.ios.apiBase") } }
    @Published var serverID: String = "vidy" { didSet { persistPreferences() } }
    @Published var appearance: String = "Dark" { didSet { persistPreferences() } }
    @Published var liveTeamAlerts = false { didSet { persistPreferences() } }
    @Published private(set) var credentialError: String?
    var onPreferencesChange: (() -> Void)?
    private let defaults: UserDefaults
    private let profileKey: String?
    private var storageEnabled = true
    private var applyingPreferences = false
    // Device-local per-profile playback choice; temporary signed URLs are not saved.
    var sportsServerPreference: String? {
        get { defaults.string(forKey: sportsServerKey) }
        set {
            guard storageEnabled else { return }
            defaults.set(newValue.map { String($0.prefix(256)) }, forKey: sportsServerKey)
        }
    }
    private var sportsServerKey: String { (profileKey ?? "streamify.ios.preferences") + ".sportsServer.v1" }
    private struct Preferences: Codable { let appearance: String; let serverID: String; var liveTeamAlerts: Bool? = nil }

    var client: TMDBClient { TMDBClient(token: tmdbToken) }
    var servers: [MediaServer] { MediaServer.bundled }

    init(defaults: UserDefaults = .standard, profileKey: String? = nil, migrateLegacy: Bool = false) {
        self.defaults = defaults
        self.profileKey = profileKey
        do { tmdbToken = try SecureCredentialStore.get("tmdbToken") ?? "" }
        catch { credentialError = error.localizedDescription }
        apiBase = defaults.string(forKey: "streamify.ios.apiBase") ?? ""
        let stored = profileKey.flatMap { defaults.data(forKey: $0) }.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        serverID = stored?.serverID ?? ((profileKey == nil || migrateLegacy) ? defaults.string(forKey: "streamify.ios.serverID") : nil) ?? "vidy"
        let storedAppearance = stored?.appearance ?? ((profileKey == nil || migrateLegacy) ? defaults.string(forKey: "streamify.ios.appearance") : nil) ?? "Dark"
        appearance = ["Dark", "Light", "System"].contains(storedAppearance) ? storedAppearance : "Dark"
        liveTeamAlerts = stored?.liveTeamAlerts ?? false
        #if DEBUG
        if PreviewFixtures.enabled { tmdbToken = PreviewFixtures.token }
        #endif
        persistPreferences()
    }
    func applyPreferences(appearance: String, serverID: String) {
        applyingPreferences = true
        self.appearance = appearance
        self.serverID = serverID
        applyingPreferences = false
    }
    func refreshDeviceConfiguration() {
        apiBase = defaults.string(forKey: "streamify.ios.apiBase") ?? ""
        #if DEBUG
        if PreviewFixtures.enabled { return }
        #endif
        do { tmdbToken = try SecureCredentialStore.get("tmdbToken") ?? "" }
        catch { credentialError = error.localizedDescription }
    }
    func discardProfilePreferences() {
        storageEnabled = false
        defaults.removeObject(forKey: sportsServerKey)
        if let profileKey { defaults.removeObject(forKey: profileKey) }
    }
    private func persistPreferences() {
        guard storageEnabled else { return }
        if let profileKey {
            if let data = try? JSONEncoder().encode(Preferences(appearance: appearance, serverID: serverID, liveTeamAlerts: liveTeamAlerts)) { defaults.set(data, forKey: profileKey) }
        } else {
            defaults.set(serverID, forKey: "streamify.ios.serverID")
            defaults.set(appearance, forKey: "streamify.ios.appearance")
        }
        if !applyingPreferences { onPreferencesChange?() }
    }
}

/// The catalog credential is protected by the device Keychain, not UserDefaults or a source file.
enum SecureCredentialStore {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "com.streamify.ios") + ".credentials" }
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    static func get(_ key: String) throws -> String? {
        var query = Self.query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
    static func set(_ value: String, for key: String) throws {
        let query = Self.query(key)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
            guard add == errSecSuccess else { throw CredentialError(status: add) }
        } else if status != errSecSuccess { throw CredentialError(status: status) }
    }
    private struct CredentialError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            if status == errSecMissingEntitlement {
                return "Keychain access requires a correctly signed app. Check the app’s signing configuration and reinstall."
            }
            return "The device could not save or read the catalog credential (\(status)). Please retry."
        }
    }
}

// Shared library contract: users/{uid}/profileLibraries/{PROFILE-UUID}/items/{kind}:{mediaKind}:{id}.
// Dates in JSON payloads are epoch milliseconds, matching the website.
private struct LibraryCloudRecord: Codable, Equatable {
    let schemaVersion: Int
    let payload: String
    let updatedAt: Double
    let deleted: Bool
    var fields: [String: Any] { ["schemaVersion": schemaVersion, "payload": payload, "updatedAt": updatedAt, "deleted": deleted] }
    init(payload: String, updatedAt: Double, deleted: Bool = false) {
        self.schemaVersion = 1; self.payload = payload; self.updatedAt = updatedAt; self.deleted = deleted
    }
    init?(_ fields: [String: Any]) {
        guard fields["schemaVersion"] as? Int == 1, let payload = fields["payload"] as? String,
              payload.utf8.count <= 100_000, let updatedAt = fields["updatedAt"] as? NSNumber,
              updatedAt.doubleValue.isFinite, let deleted = fields["deleted"] as? Bool else { return nil }
        self.init(payload: payload, updatedAt: updatedAt.doubleValue, deleted: deleted)
    }
}

@MainActor private final class LibraryCloudSync {
    private weak var library: LibraryStore?
    private let uid: String
    private let collection: CollectionReference
    private let defaults: UserDefaults
    private let key: String
    private var registration: ListenerRegistration?
    private var baseline: [String: String] = [:]
    private var records: [String: LibraryCloudRecord] = [:]
    private var pending: [String: LibraryCloudRecord] = [:]
    private var busy = Set<String>()
    private var applying = false
    private var stopped = false
    private struct Journal: Codable { let records: [String: LibraryCloudRecord]; let pending: [String: LibraryCloudRecord] }
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; e.outputFormatting = [.sortedKeys]; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }
    private static func encode<T: Encodable>(_ value: T) -> String? { (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } }
    private static func searchID(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return "search:" + (value.lowercased().addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }
    init(library: LibraryStore, uid: String, profileID: UUID, defaults: UserDefaults, storageKey: String) {
        self.library = library; self.uid = uid; self.defaults = defaults; key = storageKey + ".cloud.v1"
        collection = Firestore.firestore().collection("users").document(uid).collection("profileLibraries").document(profileID.uuidString).collection("items")
        baseline = values()
        if let data = defaults.data(forKey: key), let journal = try? JSONDecoder().decode(Journal.self, from: data) {
            records = journal.records.filter { !$0.key.hasPrefix("history:") }
            pending = journal.pending.filter { !$0.key.hasPrefix("history:") }
        } else {
            // Existing local items are imported only when no cloud item/tombstone wins.
            for (id, payload) in baseline {
                let record = LibraryCloudRecord(payload: payload, updatedAt: 0)
                records[id] = record; pending[id] = record
            }
            persist()
        }
        library.onLibraryChange = { [weak self] in self?.changed() }
        registration = collection.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, !self.stopped, Auth.auth().currentUser?.uid == self.uid else { return }
                if error != nil { self.library?.cloudSyncMessage = "Library sync unavailable. Changes are saved on this device."; return }
                guard let snapshot else { return }
                for document in snapshot.documents where !document.documentID.hasPrefix("history:") {
                    guard let incoming = LibraryCloudRecord(document.data()) else { continue }
                    let id = document.documentID
                    if incoming.updatedAt >= (self.pending[id]?.updatedAt ?? -1), incoming.updatedAt >= (self.records[id]?.updatedAt ?? -1) {
                        self.records[id] = incoming
                    }
                }
                self.apply(); self.persist(); self.flush()
            }
        }
        flush()
    }
    deinit { registration?.remove() }
    func stop() { stopped = true; registration?.remove(); registration = nil; library?.onLibraryChange = nil }
    private func values() -> [String: String] {
        guard let library else { return [:] }
        var result: [String: String] = [:]
        for media in library.saved { result["saved:" + media.key] = Self.encode(media) }
        for search in library.recentSearches { result[Self.searchID(search)] = Self.encode(search) }
        return result
    }
    private func changed() {
        guard !applying, !stopped else { return }
        let next = values()
        for id in Set(baseline.keys).union(next.keys) where baseline[id] != next[id] {
            let stamp = max(Date().timeIntervalSince1970 * 1000, (records[id]?.updatedAt ?? 0) + 1)
            let record = LibraryCloudRecord(payload: next[id] ?? "null", updatedAt: stamp, deleted: next[id] == nil)
            records[id] = record; pending[id] = record
        }
        baseline = next; persist(); flush()
    }
    private func apply() {
        guard let library, !stopped else { return }
        var saved: [MediaItem] = []; var searches: [String] = []
        for (id, record) in records.sorted(by: { $0.value.updatedAt > $1.value.updatedAt }) where !record.deleted {
            guard let data = record.payload.data(using: .utf8) else { continue }
            if id.hasPrefix("saved:"), let value = try? Self.decoder.decode(MediaItem.self, from: data) { saved.append(value) }
            if id.hasPrefix("search:"), let value = try? Self.decoder.decode(String.self, from: data) { searches.append(value) }
        }
        applying = true
        library.applyCloudLibrary(saved: saved, searches: searches)
        baseline = values(); applying = false
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(Journal(records: records, pending: pending)) { defaults.set(data, forKey: key) }
    }
    private func flush() {
        guard !stopped, let user = Auth.auth().currentUser, user.uid == uid, !user.isAnonymous else { return }
        for (id, record) in pending where !busy.contains(id) {
            busy.insert(id)
            let ref = collection.document(id), capturedUID = uid
            Firestore.firestore().runTransaction({ transaction, errorPointer -> Any? in
                do {
                    guard Auth.auth().currentUser?.uid == capturedUID else { throw ProfileSyncError.accountChanged }
                    let snapshot = try transaction.getDocument(ref)
                    if let fields = snapshot.data(), let current = LibraryCloudRecord(fields), current.updatedAt > record.updatedAt { return fields }
                    transaction.setData(record.fields, forDocument: ref)
                    return record.fields
                } catch { errorPointer?.pointee = error as NSError; return nil }
            }, completion: { [weak self] result, error in
                Task { @MainActor in
                    guard let self, !self.stopped else { return }
                    self.busy.remove(id)
                    if error != nil { self.library?.cloudSyncMessage = "Changes are saved on this device. Sync will retry when connected."; return }
                    if self.pending[id] == record { self.pending.removeValue(forKey: id) }
                    if let fields = result as? [String: Any], let winner = LibraryCloudRecord(fields), winner.updatedAt >= (self.records[id]?.updatedAt ?? -1) { self.records[id] = winner }
                    self.apply(); self.persist()
                    self.library?.cloudSyncMessage = self.pending.isEmpty ? "Library synced with your account" : "Syncing library…"
                    self.flush()
                }
            })
        }
    }
}
