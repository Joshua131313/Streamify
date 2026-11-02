import Foundation
import CoreFoundation

/// Shared with Android and web. Playback values are seconds; dates are epoch milliseconds.
struct HistorySyncEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let payload: String
    let updatedAt: Double
    let deleted: Bool

    init(payload: String, updatedAt: Double, deleted: Bool = false) {
        schemaVersion = 1; self.payload = payload; self.updatedAt = updatedAt; self.deleted = deleted
    }

    static func profileID(_ raw: String) -> String? { UUID(uuidString: raw)?.uuidString }
    static func documentID(_ entry: WatchEntry) -> String { "history:" + entry.id }
    static func validDocumentID(_ id: String) -> Bool {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "history", MediaKind(rawValue: String(parts[1])) != nil,
              let number = Int(parts[2]), number > 0, String(number) == String(parts[2]) else { return false }
        return true
    }
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder
    }
    static func encoded(_ entry: WatchEntry) -> String? {
        guard valid(entry), let data = try? encoder.encode(entry), data.count <= 100_000 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func valid(_ entry: WatchEntry) -> Bool {
        entry.media.id > 0 && entry.season > 0 && entry.episode > 0 && entry.media.rating.isFinite &&
            entry.watchedAt.timeIntervalSince1970.isFinite && entry.watchedAt.timeIntervalSince1970 >= 0 &&
            entry.positionSeconds.isFinite && entry.durationSeconds.isFinite &&
            entry.positionSeconds >= 0 && entry.durationSeconds >= 0 &&
            (entry.durationSeconds == 0 ? entry.positionSeconds == 0 : entry.positionSeconds <= entry.durationSeconds + 5)
    }
    func entry(documentID: String) -> WatchEntry? {
        guard schemaVersion == 1, updatedAt.isFinite, updatedAt >= 0, !deleted,
              Self.validDocumentID(documentID), payload.utf8.count <= 100_000,
              let data = payload.data(using: .utf8), let value = try? Self.decoder.decode(WatchEntry.self, from: data),
              Self.valid(value), Self.documentID(value) == documentID else { return nil }
        return value
    }
    func valid(documentID: String) -> Bool {
        schemaVersion == 1 && updatedAt.isFinite && updatedAt >= 0 && Self.validDocumentID(documentID) &&
            (deleted ? payload == "null" : entry(documentID: documentID) != nil)
    }
    var fields: [String: Any] { ["schemaVersion": 1, "payload": payload, "updatedAt": updatedAt, "deleted": deleted] }
    init?(fields: [String: Any], documentID: String) {
        guard let schema = fields["schemaVersion"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.doubleValue == 1,
              let stamp = fields["updatedAt"] as? NSNumber, CFGetTypeID(stamp) != CFBooleanGetTypeID(),
              let payload = fields["payload"] as? String, let deleted = fields["deleted"] as? NSNumber,
              CFGetTypeID(deleted) == CFBooleanGetTypeID() else { return nil }
        self.init(payload: payload, updatedAt: stamp.doubleValue, deleted: deleted.boolValue)
        guard valid(documentID: documentID) else { return nil }
    }
    /// Equal timestamps converge across platforms, with deletion winning a tie.
    func wins(over other: Self) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if deleted != other.deleted { return deleted }
        return payload > other.payload
    }
    func protectsFromImport(_ imported: Self, id: String) -> Bool {
        if deleted { return true }
        guard let current = entry(documentID: id), let candidate = imported.entry(documentID: id) else { return false }
        return current.season == candidate.season && current.episode == candidate.episode &&
            current.durationSeconds > 0 && candidate.durationSeconds == 0
    }
    /// Sparse legacy metadata and stale metadata-only opens must not erase known data.
    func mergingKnownData(from canonical: Self, id: String, preservePlayback: Bool = false) -> Self {
        guard let candidate = entry(documentID: id), let current = canonical.entry(documentID: id) else { return self }
        var media = candidate.media
        let placeholder = "\(media.kind.singular) \(media.id)"
        if media.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || media.title == placeholder { media.title = current.media.title }
        if media.overview.isEmpty { media.overview = current.media.overview }
        if media.posterPath.isEmpty { media.posterPath = current.media.posterPath }
        if media.backdropPath.isEmpty { media.backdropPath = current.media.backdropPath }
        if media.releaseDate.isEmpty { media.releaseDate = current.media.releaseDate }
        if media.genreIDs.isEmpty { media.genreIDs = current.media.genreIDs }
        if media.rating == 0 { media.rating = current.media.rating }
        let sameEpisode = candidate.season == current.season && candidate.episode == current.episode
        let keepPlayback = preservePlayback && sameEpisode && current.durationSeconds > 0
        let merged = WatchEntry(media: media, season: candidate.season, episode: candidate.episode,
            watchedAt: candidate.watchedAt,
            positionSeconds: keepPlayback ? current.positionSeconds : candidate.positionSeconds,
            durationSeconds: keepPlayback ? current.durationSeconds : candidate.durationSeconds)
        guard let payload = Self.encoded(merged) else { return self }
        return Self(payload: payload, updatedAt: updatedAt)
    }

    static func legacy(_ fields: [String: Any], timestamp: Double) -> Self? {
        guard let number = fields["mediaId"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded() == number.doubleValue, number.intValue > 0,
              let rawKind = fields["mediaType"] as? String, let kind = MediaKind(rawValue: rawKind),
              timestamp.isFinite, timestamp >= 0 else { return nil }
        func positive(_ value: Any?) -> Int {
            if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.intValue > 0 { return number.intValue }
            if let text = value as? String, let number = Int(text), number > 0 { return number }
            return 1
        }
        let genres = (fields["genreIds"] as? [Int]) ?? (fields["genres"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }
        let title = (fields["title"] as? String) ?? (fields["name"] as? String) ?? "\(kind.singular) \(number.intValue)"
        let media = MediaItem(id: number.intValue, kind: kind, title: title,
            overview: fields["overview"] as? String ?? "", posterPath: fields["posterPath"] as? String ?? "",
            backdropPath: fields["backdropPath"] as? String ?? "", rating: (fields["rating"] as? NSNumber)?.doubleValue ?? 0,
            releaseDate: fields["releaseDate"] as? String ?? "", genreIDs: genres.filter { $0 > 0 })
        let rawPosition = (fields["positionSeconds"] as? NSNumber)?.doubleValue ?? 0
        let rawDuration = (fields["durationSeconds"] as? NSNumber)?.doubleValue ?? 0
        let sample = PlaybackSample(position: rawPosition, duration: rawDuration)
        let entry = WatchEntry(media: media, season: positive(fields["season"]), episode: positive(fields["episode"]),
            watchedAt: Date(timeIntervalSince1970: timestamp / 1000), positionSeconds: sample?.position ?? 0, durationSeconds: sample?.duration ?? 0)
        guard let payload = encoded(entry) else { return nil }
        return Self(payload: payload, updatedAt: timestamp)
    }
}

/// Persists while disconnected, including removals made before a server read.
struct HistorySyncJournal: Codable {
    private(set) var records: [String: HistorySyncEnvelope] = [:]
    private(set) var pending: [String: HistorySyncEnvelope] = [:]
    private var baseline: [String: String] = [:]
    private var imported = Set<String>()
    private var metadataOnly = Set<String>()
    private enum CodingKeys: String, CodingKey { case records, pending, baseline, imported, metadataOnly }
    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decodeIfPresent([String: HistorySyncEnvelope].self, forKey: .records) ?? [:]
        pending = try container.decodeIfPresent([String: HistorySyncEnvelope].self, forKey: .pending) ?? [:]
        baseline = try container.decodeIfPresent([String: String].self, forKey: .baseline) ?? [:]
        imported = try container.decodeIfPresent(Set<String>.self, forKey: .imported) ?? []
        metadataOnly = try container.decodeIfPresent(Set<String>.self, forKey: .metadataOnly) ?? []
    }
    func isImport(_ id: String) -> Bool { imported.contains(id) }
    func isMetadataOnly(_ id: String) -> Bool { metadataOnly.contains(id) }

    @discardableResult mutating func captureLocal(_ entries: [WatchEntry], now: Double, initial: Bool = false,
                                                metadataOnlyChange: Bool = false) -> Bool {
        let values = Dictionary(entries.compactMap { entry -> (String, String)? in
            HistorySyncEnvelope.encoded(entry).map { (HistorySyncEnvelope.documentID(entry), $0) }
        }, uniquingKeysWith: { first, _ in first })
        var changed = false
        // Missing visible rows can be the 200-item display cap, never an implicit delete.
        for id in values.keys where baseline[id] != values[id] {
            if metadataOnlyChange && records[id]?.deleted == true { continue }
            let original = entries.first { HistorySyncEnvelope.documentID($0) == id }?.watchedAt.timeIntervalSince1970 ?? 0
            let existingCheckpoint = metadataOnlyChange && pending[id] != nil && !metadataOnly.contains(id)
            let stamp = existingCheckpoint ? pending[id]!.updatedAt : initial ? original * 1000 : max(now, (records[id]?.updatedAt ?? 0) + 1)
            let record = HistorySyncEnvelope(payload: values[id]!, updatedAt: max(0, stamp))
            records[id] = record; pending[id] = record
            if initial { imported.insert(id) } else if !existingCheckpoint { imported.remove(id) }
            if metadataOnlyChange && !existingCheckpoint { metadataOnly.insert(id) }
            else if !metadataOnlyChange { metadataOnly.remove(id) }
            changed = true
        }
        baseline = values
        return changed
    }
    mutating func remove(_ ids: Set<String>, now: Double) {
        for id in ids where HistorySyncEnvelope.validDocumentID(id) {
            let record = HistorySyncEnvelope(payload: "null", updatedAt: max(now, (records[id]?.updatedAt ?? 0) + 1), deleted: true)
            records[id] = record; pending[id] = record; baseline.removeValue(forKey: id)
            imported.remove(id); metadataOnly.remove(id)
        }
    }
    mutating func mergeServer(_ incoming: [String: HistorySyncEnvelope]) {
        for (id, record) in incoming where record.valid(documentID: id) {
            if metadataOnly.contains(id), let queued = pending[id], !record.deleted {
                let merged = queued.mergingKnownData(from: record, id: id, preservePlayback: true)
                records[id] = merged; pending[id] = merged
            } else if imported.contains(id), let queued = pending[id] {
                let merged = queued.mergingKnownData(from: record, id: id)
                records[id] = merged; pending[id] = merged
            }
            let local = records[id]
            let importLoses = imported.contains(id) && local.map { record.protectsFromImport($0, id: id) } == true
            let metadataLoses = metadataOnly.contains(id) && record.deleted
            if local == nil || record == local || record.wins(over: local!) || importLoses || metadataLoses {
                records[id] = local.map { record.mergingKnownData(from: $0, id: id) } ?? record
                if let queued = pending[id], queued == record || record.wins(over: queued) || importLoses || metadataLoses {
                    pending.removeValue(forKey: id); imported.remove(id); metadataOnly.remove(id)
                }
            }
        }
    }
    mutating func importLegacy(_ incoming: [String: HistorySyncEnvelope]) {
        for (id, record) in incoming where record.valid(documentID: id) && !record.deleted {
            var candidate = record
            if let current = records[id] {
                if current.protectsFromImport(record, id: id) { continue }
                guard record.wins(over: current) else { continue }
                candidate = record.mergingKnownData(from: current, id: id)
            }
            records[id] = candidate; pending[id] = candidate; imported.insert(id); metadataOnly.remove(id)
        }
    }
    mutating func acknowledge(id: String, sent: HistorySyncEnvelope, winner: HistorySyncEnvelope) {
        guard winner.valid(documentID: id) else { return }
        if pending[id] == sent {
            pending.removeValue(forKey: id); imported.remove(id); metadataOnly.remove(id)
            records[id] = winner
        } else { mergeServer([id: winner]) }
    }
    mutating func visibleEntries() -> [WatchEntry] {
        let entries = records.compactMap { $0.value.entry(documentID: $0.key) }.sorted {
            $0.watchedAt == $1.watchedAt ? $0.id < $1.id : $0.watchedAt > $1.watchedAt
        }
        let visible = Array(entries.prefix(200))
        baseline = Dictionary(visible.compactMap { entry in HistorySyncEnvelope.encoded(entry).map { (HistorySyncEnvelope.documentID(entry), $0) } }, uniquingKeysWith: { first, _ in first })
        return visible
    }
}
