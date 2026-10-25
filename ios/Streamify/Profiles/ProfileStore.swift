import Foundation
import Combine

enum ProfileAvatar: String, Codable, CaseIterable, Identifiable {
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
    // Persisted color IDs stay unchanged so existing profiles retain their avatar.
    var artworkName: String { "profile-avatar-\(rawValue)" }
}

struct AppProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var avatar: ProfileAvatar
}

/// Each profile owns a separate library object. A player finishing an async
/// checkpoint after a switch still writes to the profile that started it.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [AppProfile]
    @Published private(set) var activeProfile: AppProfile?
    @Published private(set) var library: LibraryStore
    @Published private(set) var requiresSelection: Bool
    private let defaults: UserDefaults
    private var libraries: [UUID: LibraryStore] = [:]
    private static let key = "streamify.ios.profiles.v1"
    private static let migrationKey = "streamify.ios.profiles.guestLibraryMigrated.v1"

    private struct Snapshot: Codable {
        var profiles: [AppProfile]
        var selectedID: UUID?
    }

    init(defaults: UserDefaults = .standard, chooseOnLaunch: Bool = true) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        var seen = Set<UUID>()
        let restored = decoded?.profiles.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted
        } ?? []
        let existing = Array(restored.prefix(5))
        let values = existing.isEmpty ? [AppProfile(id: UUID(), name: "My profile", avatar: .crimson)] : existing
        profiles = values
        let selected = values.first { $0.id == decoded?.selectedID } ?? values[0]
        activeProfile = selected
        requiresSelection = chooseOnLaunch
        // Import the old device library once into the original first profile.
        // Keep its old bytes as a recovery copy; never import them into a new profile.
        if !defaults.bool(forKey: Self.migrationKey) {
            let destination = Self.libraryKey(values[0].id)
            if defaults.data(forKey: destination) == nil,
               let legacy = defaults.data(forKey: "streamify.ios.guestLibrary.v1") {
                defaults.set(legacy, forKey: destination)
            }
            defaults.set(true, forKey: Self.migrationKey)
        }
        library = LibraryStore(defaults: defaults, storageKey: Self.libraryKey(selected.id))
        libraries[selected.id] = library
        persist()
    }

    func select(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        if activeProfile?.id != id {
            library = libraries[id] ?? LibraryStore(defaults: defaults, storageKey: Self.libraryKey(id))
            libraries[id] = library
        }
        activeProfile = profile
        persist()
        requiresSelection = false
    }

    func showChooser() { requiresSelection = true }
    func cancelSwitch() { if activeProfile != nil { requiresSelection = false } }

    func add(name: String, avatar: ProfileAvatar) throws {
        guard profiles.count < 5 else { throw ProfileError.limit }
        let clean = try validName(name)
        profiles.append(AppProfile(id: UUID(), name: clean, avatar: avatar))
        persist()
    }

    func update(id: UUID, name: String, avatar: ProfileAvatar) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        profiles[index].name = try validName(name)
        profiles[index].avatar = avatar
        if activeProfile?.id == id { activeProfile = profiles[index] }
        persist()
    }

    func remove(_ id: UUID) throws {
        guard profiles.count > 1 else { throw ProfileError.last }
        guard profiles.contains(where: { $0.id == id }) else { throw ProfileError.missing }
        if let removed = libraries.removeValue(forKey: id) { removed.discardStorage() }
        else { defaults.removeObject(forKey: Self.libraryKey(id)) }
        profiles.removeAll { $0.id == id }
        if activeProfile?.id == id {
            activeProfile = profiles[0]
            let fallback = profiles[0].id
            library = libraries[fallback] ?? LibraryStore(defaults: defaults, storageKey: Self.libraryKey(fallback))
            libraries[fallback] = library
            requiresSelection = true
        }
        persist()
    }

    private func validName(_ value: String) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 24,
              !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ProfileError.name }
        return clean
    }

    private static func libraryKey(_ id: UUID) -> String { "streamify.ios.profileLibrary.\(id.uuidString).v1" }
    private func persist() {
        let snapshot = Snapshot(profiles: profiles, selectedID: activeProfile?.id)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
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
