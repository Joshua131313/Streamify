import Foundation
import Combine
import Security

/// Device-only library. Cloud account data is never mixed into this guest store.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var saved: [MediaItem] = []
    @Published private(set) var history: [WatchEntry] = []
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var followedTeams: [String] = []
    @Published var favoriteGenres: [Int] = [] { didSet { persist(); preferencesChanged() } }
    var onPreferencesChange: (() -> Void)?
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
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "streamify.ios.guestLibrary.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            var seen = Set<String>()
            saved = snapshot.saved.filter { seen.insert($0.key).inserted }
            seen.removeAll()
            history = Array(snapshot.history.sorted { $0.watchedAt > $1.watchedAt }.filter { seen.insert($0.id).inserted }.prefix(200))
            recentSearches = Array(snapshot.recentSearches.prefix(20))
            followedTeams = Array(Set(snapshot.followedTeams)).sorted()
            favoriteGenres = snapshot.favoriteGenres
        }
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
        persist()
    }

    func repairHistoryArtwork(_ media: MediaItem) {
        guard storageEnabled, let index = history.firstIndex(where: { $0.id == media.key }) else { return }
        let old = history[index]
        let repaired = media.preservingArtwork(from: old.media)
        guard repaired != old.media else { return }
        history[index] = WatchEntry(media: repaired, season: old.season, episode: old.episode, watchedAt: old.watchedAt,
                                   positionSeconds: old.positionSeconds, durationSeconds: old.durationSeconds)
        persist()
    }

    func removeHistory(_ entry: WatchEntry) { history.removeAll { $0.id == entry.id }; persist() }
    func removeHistory(_ media: MediaItem) { history.removeAll { $0.id == media.key }; persist() }
    func clearHistory() { history = []; persist() }

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
    func discardStorage() { storageEnabled = false; defaults.removeObject(forKey: storageKey) }

    private func persist() {
        guard storageEnabled else { return }
        let snapshot = Snapshot(saved: saved, history: history, recentSearches: recentSearches,
            followedTeams: followedTeams, favoriteGenres: favoriteGenres)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: storageKey) }
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
    @Published private(set) var credentialError: String?
    var onPreferencesChange: (() -> Void)?
    private let defaults: UserDefaults
    private let profileKey: String?
    private var storageEnabled = true
    private var applyingPreferences = false
    private struct Preferences: Codable { let appearance: String; let serverID: String }

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
        if let profileKey { defaults.removeObject(forKey: profileKey) }
    }
    private func persistPreferences() {
        guard storageEnabled else { return }
        if let profileKey {
            if let data = try? JSONEncoder().encode(Preferences(appearance: appearance, serverID: serverID)) { defaults.set(data, forKey: profileKey) }
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
