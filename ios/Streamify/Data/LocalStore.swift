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
    @Published var favoriteGenres: [Int] = [] { didSet { persist() } }
    private let defaults: UserDefaults
    private let storageKey = "streamify.ios.guestLibrary.v1"

    private struct Snapshot: Codable {
        var saved: [MediaItem]
        var history: [WatchEntry]
        var recentSearches: [String]
        var followedTeams: [String]
        var favoriteGenres: [Int]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        let entry = WatchEntry(media: media, season: max(1, season), episode: max(1, episode), watchedAt: Date(),
            positionSeconds: position.isFinite ? max(0, position) : 0,
            durationSeconds: duration.isFinite ? max(0, duration) : 0)
        history.removeAll { $0.id == media.key }
        history.insert(entry, at: 0)
        history = Array(history.prefix(200))
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
    }
    func setGenre(_ id: Int) {
        if favoriteGenres.contains(id) { favoriteGenres.removeAll { $0 == id } }
        else if id > 0 { favoriteGenres.append(id) }
    }

    private func persist() {
        let snapshot = Snapshot(saved: saved, history: history, recentSearches: recentSearches,
            followedTeams: followedTeams, favoriteGenres: favoriteGenres)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: storageKey) }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var tmdbToken: String = "" {
        didSet {
            do { try SecureCredentialStore.set(tmdbToken, for: "tmdbToken"); credentialError = nil }
            catch { credentialError = error.localizedDescription }
        }
    }
    @Published var apiBase: String = "" { didSet { defaults.set(apiBase, forKey: "streamify.ios.apiBase") } }
    @Published var serverID: String = "vidy" { didSet { defaults.set(serverID, forKey: "streamify.ios.serverID") } }
    @Published var appearance: String = "Dark" { didSet { defaults.set(appearance, forKey: "streamify.ios.appearance") } }
    @Published private(set) var credentialError: String?
    private let defaults: UserDefaults

    var client: TMDBClient { TMDBClient(token: tmdbToken) }
    var servers: [MediaServer] { MediaServer.bundled }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do { tmdbToken = try SecureCredentialStore.get("tmdbToken") ?? "" }
        catch { credentialError = error.localizedDescription }
        apiBase = defaults.string(forKey: "streamify.ios.apiBase") ?? ""
        serverID = defaults.string(forKey: "streamify.ios.serverID") ?? "vidy"
        let storedAppearance = defaults.string(forKey: "streamify.ios.appearance") ?? "Dark"
        appearance = ["Dark", "Light", "System"].contains(storedAppearance) ? storedAppearance : "Dark"
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
        var errorDescription: String? { "The device could not save or read the catalog credential (\(status)). Please unlock your iPhone and retry." }
    }
}
