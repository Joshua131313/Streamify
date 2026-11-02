import Foundation
import XCTest
@testable import Streamify

@MainActor final class HistorySyncTests: XCTestCase {
    private func entry(_ id: Int = 1399, episode: Int = 3, position: Double = 1234.5, duration: Double = 3600, stamp: Double = 1_793_583_000_000) -> WatchEntry {
        WatchEntry(media: MediaItem(id: id, kind: .tv, title: "Show \(id)", posterPath: "/poster.jpg"), season: 2,
            episode: episode, watchedAt: Date(timeIntervalSince1970: stamp / 1000), positionSeconds: position, durationSeconds: duration)
    }
    private func envelope(_ entry: WatchEntry, stamp: Double? = nil) throws -> HistorySyncEnvelope {
        HistorySyncEnvelope(payload: try XCTUnwrap(HistorySyncEnvelope.encoded(entry)), updatedAt: stamp ?? entry.watchedAt.timeIntervalSince1970 * 1000)
    }
    private func metadata(_ entry: WatchEntry, update: (inout MediaItem) -> Void) -> WatchEntry {
        var media = entry.media; update(&media)
        return WatchEntry(media: media, season: entry.season, episode: entry.episode, watchedAt: entry.watchedAt,
            positionSeconds: entry.positionSeconds, durationSeconds: entry.durationSeconds)
    }
    private func store(_ key: String = "profile", defaults: UserDefaults? = nil) -> LibraryStore {
        LibraryStore(defaults: defaults ?? UserDefaults(suiteName: "HistorySyncTests.\(UUID().uuidString)")!, storageKey: key)
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("History synchronization did not reach its expected state", file: file, line: line)
    }

    func testSharedGoldenFixtureUsesExactMediaFieldsMillisecondsAndCanonicalProfileID() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "history-sync", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let raw = try XCTUnwrap(fixture["entry"] as? [String: Any])
        let value = try HistorySyncEnvelope.decoder.decode(WatchEntry.self, from: JSONSerialization.data(withJSONObject: raw))
        let payload = try XCTUnwrap(HistorySyncEnvelope.encoded(value))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual(NSDictionary(dictionary: raw), NSDictionary(dictionary: encoded))
        XCTAssertEqual(HistorySyncEnvelope.documentID(value), fixture["documentID"] as? String)
        XCTAssertEqual(HistorySyncEnvelope.profileID(try XCTUnwrap(fixture["profileID"] as? String)), fixture["canonicalProfileID"] as? String)
        XCTAssertEqual(value.watchedAt.timeIntervalSince1970 * 1000, fixture["updatedAt"] as? Double)
        XCTAssertEqual(value.positionSeconds, 1234.5)
        XCTAssertEqual(PlaybackIdentity(mediaKey: value.id, season: 2, episode: 3).resumeSeconds(from: value), 1234.5)
        let legacy = try XCTUnwrap(fixture["legacy"] as? [String: Any])
        let migrated = try XCTUnwrap(HistorySyncEnvelope.legacy(legacy, timestamp: value.watchedAt.timeIntervalSince1970 * 1000))
        XCTAssertEqual(migrated.entry(documentID: "history:tv:1399")?.positionSeconds, value.positionSeconds)
        XCTAssertEqual(migrated.updatedAt, value.watchedAt.timeIntervalSince1970 * 1000)
    }

    func testMalformedIdentitiesProgressAndEnvelopeVersionsAreRejected() throws {
        for id in ["history:tv:0", "history:tv:-1", "history:tv:01", "history:series:1399", "history:tv:1/other", "saved:tv:1399"] {
            XCTAssertFalse(HistorySyncEnvelope.validDocumentID(id), id)
        }
        let record = try envelope(entry())
        XCTAssertNil(record.entry(documentID: "history:tv:1400"))
        var fields = record.fields; fields["schemaVersion"] = 2
        XCTAssertNil(HistorySyncEnvelope(fields: fields, documentID: "history:tv:1399"))
        fields = record.fields; fields["updatedAt"] = Double.infinity
        XCTAssertNil(HistorySyncEnvelope(fields: fields, documentID: "history:tv:1399"))
        XCTAssertNil(HistorySyncEnvelope.encoded(entry(position: .nan)))
        XCTAssertNil(HistorySyncEnvelope.encoded(entry(position: 4000)))
        XCTAssertNil(HistorySyncEnvelope.encoded(entry(position: 12, duration: 0)))
    }

    func testLocalImportDoesNotResurrectCanonicalTombstoneAndDeletionWinsEqualTimestamp() throws {
        var journal = HistorySyncJournal()
        journal.captureLocal([entry()], now: 9_000_000_000_000, initial: true)
        let tombstone = HistorySyncEnvelope(payload: "null", updatedAt: 1000, deleted: true)
        journal.mergeServer(["history:tv:1399": tombstone])
        XCTAssertTrue(journal.visibleEntries().isEmpty)
        XCTAssertTrue(journal.pending.isEmpty)
        let active = try envelope(entry(), stamp: 1000)
        XCTAssertTrue(tombstone.wins(over: active))
        XCTAssertFalse(active.wins(over: tombstone))
    }

    func testNewerEpisodeWinsAndResumeNeverBorrowsAnotherEpisodeOrCompletedProgress() throws {
        var journal = HistorySyncJournal()
        let old = entry(episode: 3), new = entry(episode: 4, position: 300, stamp: 1_793_583_001_000)
        journal.captureLocal([old], now: 0, initial: true)
        journal.mergeServer(["history:tv:1399": try envelope(new)])
        let merged = try XCTUnwrap(journal.visibleEntries().first)
        XCTAssertEqual(merged.episode, 4); XCTAssertEqual(merged.positionSeconds, 300)
        XCTAssertEqual(PlaybackIdentity(mediaKey: merged.id, season: 2, episode: 3).resumeSeconds(from: merged), 0)
        XCTAssertEqual(PlaybackIdentity(mediaKey: merged.id, season: 2, episode: 4).resumeSeconds(from: merged), 300)
        let completed = entry(position: 3420)
        XCTAssertTrue(completed.completed)
        XCTAssertEqual(PlaybackIdentity(mediaKey: completed.id, season: 2, episode: 3).resumeSeconds(from: completed), 0)
    }

    func testLegacyMissingProgressCannotEraseRealCheckpointOrCanonicalDeletion() throws {
        var journal = HistorySyncJournal()
        let current = try envelope(entry(), stamp: 1000)
        journal.mergeServer(["history:tv:1399": current])
        let legacy = try envelope(entry(position: 0, duration: 0), stamp: 9000)
        journal.importLegacy(["history:tv:1399": legacy])
        XCTAssertEqual(journal.visibleEntries().first?.positionSeconds, 1234.5)
        journal.mergeServer(["history:tv:1399": HistorySyncEnvelope(payload: "null", updatedAt: 10_000, deleted: true)])
        journal.importLegacy(["history:tv:1399": try envelope(entry(), stamp: 20_000)])
        XCTAssertTrue(journal.visibleEntries().isEmpty)
    }

    func testJournalSurvivesDisconnectedCheckpointsAndClearWithoutResurrection() throws {
        let defaults = UserDefaults(suiteName: "HistoryJournal.\(UUID().uuidString)")!
        let first = store("alice:profile", defaults: defaults)
        first.record(entry().media, season: 2, episode: 3, positionSeconds: 200, durationSeconds: 3600)
        let reloaded = store("alice:profile", defaults: defaults)
        XCTAssertEqual(reloaded.history.first?.positionSeconds, 200)
        XCTAssertEqual(reloaded.historySyncJournal.pending.count, 1)
        reloaded.record(entry().media, season: 2, episode: 3, positionSeconds: 600, durationSeconds: 3600)
        let afterProgress = store("alice:profile", defaults: defaults)
        XCTAssertEqual(afterProgress.history.first?.positionSeconds, 600)
        afterProgress.clearHistory()
        let afterClear = store("alice:profile", defaults: defaults)
        XCTAssertTrue(afterClear.history.isEmpty)
        XCTAssertTrue(try XCTUnwrap(afterClear.historySyncJournal.pending["history:tv:1399"]).deleted)
        let legacy = try envelope(entry())
        afterClear.updateHistoryJournal { $0.importLegacy(["history:tv:1399": legacy]) }
        XCTAssertTrue(afterClear.history.isEmpty)
        XCTAssertTrue(store("bob:profile", defaults: defaults).history.isEmpty)
        XCTAssertTrue(store("alice:other", defaults: defaults).history.isEmpty)
    }

    func testAcknowledgingOldWriteDoesNotDropANewerOfflineCheckpoint() throws {
        var journal = HistorySyncJournal()
        journal.captureLocal([entry(position: 100)], now: 1000)
        let old = try XCTUnwrap(journal.pending["history:tv:1399"])
        journal.captureLocal([entry(position: 300)], now: 2000)
        journal.acknowledge(id: "history:tv:1399", sent: old, winner: old)
        XCTAssertEqual(journal.pending["history:tv:1399"]?.entry(documentID: "history:tv:1399")?.positionSeconds, 300)
    }

    func testServerReadAndTransactionFailuresRetryWithoutDroppingLocalProgress() async throws {
        let library = store(), backend = HistoryBackendFake(), profile = UUID()
        library.record(entry().media, season: 2, episode: 3, positionSeconds: 400, durationSeconds: 3600)
        backend.loadFailures = 1; backend.writeFailures = 1
        let sync = HistoryCloudSync(library: library, uid: "alice", profileID: profile, firstProfileID: profile,
            backend: backend, retrySeconds: 0.01, identityValid: { true })
        XCTAssertEqual(library.history.first?.positionSeconds, 400)
        await eventually { backend.writeCount >= 2 && library.historySyncJournal.pending.isEmpty }
        XCTAssertGreaterThanOrEqual(backend.loadCount, 2)
        XCTAssertEqual(backend.documents[backend.scope("alice", profile)]?["history:tv:1399"]?.entry(documentID: "history:tv:1399")?.positionSeconds, 400)
        sync.stop()
    }

    func testStoppedAccountSessionIgnoresLateReadAndDoesNotUploadToAnotherProfile() async throws {
        let library = store(), backend = HistoryBackendFake(), profile = UUID()
        backend.holdRead = true
        let sync = HistoryCloudSync(library: library, uid: "alice", profileID: profile, firstProfileID: profile,
            backend: backend, identityValid: { true })
        await eventually { backend.readContinuation != nil }
        sync.stop()
        backend.readContinuation?.resume(returning: ["history:tv:1399": try envelope(entry())]); backend.readContinuation = nil
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(library.history.isEmpty); XCTAssertEqual(backend.writeCount, 0)
        XCTAssertNil(backend.listeners[backend.scope("alice", profile)])
    }

    func testFrozenLegacyTargetDoesNotMoveWhenOriginalProfileIsDeleted() async throws {
        let backend = HistoryBackendFake(), original = UUID(), replacement = UUID()
        backend.target = original; backend.legacy = ["history:tv:1399": try envelope(entry())]
        let other = store()
        let sync = HistoryCloudSync(library: other, uid: "alice", profileID: replacement, firstProfileID: replacement,
            backend: backend, identityValid: { true })
        await eventually { other.historySyncMessage?.contains("synced") == true }
        XCTAssertEqual(backend.target, original); XCTAssertEqual(backend.legacyReadCount, 0)
        XCTAssertTrue(other.history.isEmpty); sync.stop()
    }

    func testRealtimeRemoteProgressUpdatesTheSameProfileAndListenerStopsOnDisconnect() async throws {
        let backend = HistoryBackendFake(), profile = UUID(), library = store()
        let sync = HistoryCloudSync(library: library, uid: "alice", profileID: profile, firstProfileID: profile,
            backend: backend, identityValid: { true })
        await eventually { backend.listeners[backend.scope("alice", profile)] != nil }
        backend.listeners[backend.scope("alice", profile)]?(.success(["history:tv:1399": try envelope(entry(position: 900))]))
        XCTAssertEqual(library.history.first?.positionSeconds, 900)
        sync.stop()
        XCTAssertNil(backend.listeners[backend.scope("alice", profile)])
    }

    func testAccountChangeIgnoresLateWriteAcknowledgmentAndRetainsItsPendingCheckpoint() async throws {
        let backend = HistoryBackendFake(), profile = UUID(), library = store()
        library.record(entry().media, season: 2, episode: 3, positionSeconds: 750, durationSeconds: 3600)
        backend.holdWrite = true
        var signedIn = true
        let sync = HistoryCloudSync(library: library, uid: "alice", profileID: profile, firstProfileID: profile,
            backend: backend, identityValid: { signedIn })
        await eventually { backend.writeContinuation != nil }
        signedIn = false; sync.stop()
        let pending = try XCTUnwrap(library.historySyncJournal.pending["history:tv:1399"])
        backend.writeContinuation?.resume(returning: pending); backend.writeContinuation = nil
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(library.historySyncJournal.pending["history:tv:1399"], pending)
        XCTAssertEqual(library.history.first?.positionSeconds, 750)
        XCTAssertTrue(store("bob:profile").history.isEmpty)
    }

    func testFailedRealtimeListenerReconnectsWithoutErasingTheVisibleHistory() async throws {
        let backend = HistoryBackendFake(), profile = UUID(), library = store()
        backend.documents[backend.scope("alice", profile)] = ["history:tv:1399": try envelope(entry(position: 900))]
        let sync = HistoryCloudSync(library: library, uid: "alice", profileID: profile, firstProfileID: profile,
            backend: backend, retrySeconds: 0.01, identityValid: { true })
        await eventually { library.historySyncMessage?.contains("synced") == true }
        backend.listeners[backend.scope("alice", profile)]?(.failure(ProfileSyncError.unavailable))
        XCTAssertEqual(library.history.first?.positionSeconds, 900)
        await eventually { backend.loadCount >= 2 && library.historySyncMessage?.contains("synced") == true }
        XCTAssertEqual(library.history.first?.positionSeconds, 900); sync.stop()
    }

    func testHistoryDisplayCapDoesNotDeleteEvictedCloudRowsButExplicitClearDoes() throws {
        let library = store()
        for id in 1...201 {
            library.record(MediaItem(id: id, kind: .tv, title: "Title \(id)"), positionSeconds: 100, durationSeconds: 3600)
        }
        XCTAssertEqual(library.history.count, 200)
        XCTAssertFalse(try XCTUnwrap(library.historySyncJournal.records["history:tv:1"]).deleted)
        XCTAssertFalse(try XCTUnwrap(library.historySyncJournal.pending["history:tv:1"]).deleted)
        XCTAssertEqual(library.historySyncJournal.records.count, 201)
        library.clearHistory()
        XCTAssertTrue(library.history.isEmpty)
        XCTAssertEqual(library.historySyncJournal.pending.count, 201)
        XCTAssertTrue(library.historySyncJournal.pending.values.allSatisfy(\.deleted))
    }

    func testMetadataOnlyWritePreservesTransactionCurrentProgressWhileActualSeekCanMoveBackward() async throws {
        let library = store(), backend = HistoryBackendFake(), profile = UUID()
        library.record(entry().media, season: 2, episode: 3, positionSeconds: 100, durationSeconds: 3600)
        let old = try XCTUnwrap(library.historySyncJournal.pending["history:tv:1399"])
        library.updateHistoryJournal { $0.acknowledge(id: "history:tv:1399", sent: old, winner: old) }
        library.record(entry().media, season: 2, episode: 3)
        XCTAssertTrue(library.historySyncJournal.isMetadataOnly("history:tv:1399"))
        let queued = try XCTUnwrap(library.historySyncJournal.pending["history:tv:1399"])
        let remoteCheckpoint = try envelope(entry(position: 200), stamp: queued.updatedAt - 1)
        backend.documents[backend.scope("alice", profile)] = ["history:tv:1399": old]
        backend.beforeCommit = { backend.documents[backend.scope("alice", profile)] = ["history:tv:1399": remoteCheckpoint] }
        let sync = HistoryCloudSync(library: library, uid: "alice", profileID: profile, firstProfileID: profile,
            backend: backend, identityValid: { true })
        await eventually { backend.writeCount >= 1 && library.historySyncJournal.pending.isEmpty }
        XCTAssertEqual(backend.metadataModes.first, true)
        XCTAssertEqual(library.history.first?.positionSeconds, 200)
        library.record(entry().media, season: 2, episode: 3, positionSeconds: 20, durationSeconds: 3600)
        await eventually { backend.writeCount >= 2 && library.historySyncJournal.pending.isEmpty }
        XCTAssertEqual(backend.metadataModes.last, false)
        XCTAssertEqual(library.history.first?.positionSeconds, 20)
        sync.stop()
    }

    func testMetadataRepairsDoNotFreshenAnOlderQueuedRealCheckpointAndModesSurviveRelaunch() throws {
        var journal = HistorySyncJournal()
        journal.captureLocal([entry(position: 100)], now: 1000)
        let repaired = metadata(entry(position: 100)) { $0.overview = "Repaired metadata" }
        journal.captureLocal([repaired], now: 9000, metadataOnlyChange: true)
        XCTAssertEqual(journal.pending["history:tv:1399"]?.updatedAt, 1000)
        XCTAssertFalse(journal.isMetadataOnly("history:tv:1399"))
        let checkpoint = try XCTUnwrap(journal.pending["history:tv:1399"])
        journal.acknowledge(id: "history:tv:1399", sent: checkpoint, winner: checkpoint)
        let newer = metadata(repaired) { $0.overview = "Newer metadata repair" }
        journal.captureLocal([newer], now: 10_000, metadataOnlyChange: true)
        let restored = try JSONDecoder().decode(HistorySyncJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertTrue(restored.isMetadataOnly("history:tv:1399"))
        XCTAssertEqual(restored.pending["history:tv:1399"]?.updatedAt, 10_000)
    }

    func testOlderJournalWithoutNewModeFieldsKeepsPersistentDeletionTombstones() throws {
        let tombstone = HistorySyncEnvelope(payload: "null", updatedAt: 9000, deleted: true)
        let previous: [String: Any] = ["records": ["history:tv:1399": tombstone.fields],
            "pending": ["history:tv:1399": tombstone.fields], "baseline": [:]]
        var restored = try JSONDecoder().decode(HistorySyncJournal.self, from: JSONSerialization.data(withJSONObject: previous))
        XCTAssertTrue(try XCTUnwrap(restored.pending["history:tv:1399"]).deleted)
        restored.importLegacy(["history:tv:1399": try envelope(entry(), stamp: 20_000)])
        XCTAssertTrue(restored.visibleEntries().isEmpty)
        XCTAssertTrue(try XCTUnwrap(restored.pending["history:tv:1399"]).deleted)
    }

    func testNewerSparseLegacyProgressPreservesKnownCanonicalTitleAndArtwork() throws {
        var journal = HistorySyncJournal()
        let rich = metadata(entry(position: 100)) {
            $0.title = "Actual title"; $0.overview = "Known overview"
            $0.backdropPath = "/known-backdrop.jpg"; $0.genreIDs = [18]
        }
        journal.mergeServer(["history:tv:1399": try envelope(rich, stamp: 1000)])
        let sparse = metadata(entry(position: 200)) {
            $0.title = "Series 1399"; $0.posterPath = ""; $0.backdropPath = ""
        }
        journal.importLegacy(["history:tv:1399": try envelope(sparse, stamp: 2000)])
        let migrated = try XCTUnwrap(journal.visibleEntries().first)
        XCTAssertEqual(migrated.positionSeconds, 200)
        XCTAssertEqual(migrated.media.title, "Actual title")
        XCTAssertEqual(migrated.media.posterPath, "/poster.jpg")
        XCTAssertEqual(migrated.media.backdropPath, "/known-backdrop.jpg")
        XCTAssertEqual(migrated.media.overview, "Known overview")
        XCTAssertEqual(journal.pending["history:tv:1399"]?.updatedAt, 2000)
    }

    func testMetadataOnlyReopeningDoesNotReplaceAnOfflinePendingDeletion() throws {
        let library = store()
        library.record(entry().media, season: 2, episode: 3, positionSeconds: 100, durationSeconds: 3600)
        library.removeHistory(entry().media)
        let deletion = try XCTUnwrap(library.historySyncJournal.pending["history:tv:1399"])
        library.record(entry().media, season: 2, episode: 3)
        XCTAssertEqual(library.historySyncJournal.pending["history:tv:1399"], deletion)
        XCTAssertTrue(deletion.deleted)
    }

    func testMetadataOpenForAnotherEpisodeGetsFreshTimestampAndMetadataOnlyMode() throws {
        var journal = HistorySyncJournal()
        journal.captureLocal([entry(episode: 3, position: 100)], now: 1000)
        journal.captureLocal([entry(episode: 4, position: 0, duration: 0)], now: 9000, metadataOnlyChange: true)
        let pending = try XCTUnwrap(journal.pending["history:tv:1399"])
        XCTAssertEqual(pending.updatedAt, 9000)
        XCTAssertTrue(journal.isMetadataOnly("history:tv:1399"))
        XCTAssertFalse(journal.isImport("history:tv:1399"))
        XCTAssertEqual(pending.entry(documentID: "history:tv:1399")?.episode, 4)
        XCTAssertEqual(pending.entry(documentID: "history:tv:1399")?.positionSeconds, 0)
    }

    func testSharedUnavailableTitlePlaceholderCannotEraseKnownCanonicalMetadata() throws {
        let rich = metadata(entry(position: 100)) {
            $0.title = "Actual title"; $0.overview = "Known overview"; $0.backdropPath = "/known-backdrop.jpg"
        }
        let sparse = metadata(entry(position: 200)) {
            $0.title = "Unavailable title #1399"; $0.posterPath = ""; $0.backdropPath = ""
        }
        var journal = HistorySyncJournal()
        journal.mergeServer(["history:tv:1399": try envelope(rich, stamp: 1000)])
        journal.importLegacy(["history:tv:1399": try envelope(sparse, stamp: 2000)])
        let migrated = try XCTUnwrap(journal.visibleEntries().first)
        XCTAssertEqual(migrated.media.title, "Actual title")
        XCTAssertEqual(migrated.media.posterPath, "/poster.jpg")
        XCTAssertEqual(migrated.media.backdropPath, "/known-backdrop.jpg")
        XCTAssertEqual(migrated.positionSeconds, 200)
    }

    func testPassiveLegacyImportCannotReplaceExplicitPendingPutsOrDeletes() throws {
        let id = "history:tv:1399"
        let legacy = try envelope(entry(position: 800), stamp: 90_000)
        var checkpoint = HistorySyncJournal()
        checkpoint.captureLocal([entry(position: 100)], now: 1000)
        let original = try XCTUnwrap(checkpoint.pending[id])
        checkpoint.importLegacy([id: legacy])
        XCTAssertEqual(checkpoint.pending[id], original)
        XCTAssertFalse(checkpoint.isImport(id))
        checkpoint.remove([id], now: 2000)
        let deletion = try XCTUnwrap(checkpoint.pending[id])
        checkpoint.importLegacy([id: legacy])
        XCTAssertEqual(checkpoint.pending[id], deletion)
        XCTAssertTrue(deletion.deleted)

        var metadataOpen = HistorySyncJournal()
        metadataOpen.captureLocal([entry(position: 0, duration: 0)], now: 3000, metadataOnlyChange: true)
        let open = try XCTUnwrap(metadataOpen.pending[id])
        metadataOpen.importLegacy([id: legacy])
        XCTAssertEqual(metadataOpen.pending[id], open)
        XCTAssertTrue(metadataOpen.isMetadataOnly(id))
    }
}

@MainActor private final class HistoryBackendFake: HistorySyncBackend {
    var documents: [String: [String: HistorySyncEnvelope]] = [:]
    var listeners: [String: (Result<[String: HistorySyncEnvelope], Error>) -> Void] = [:]
    var target: UUID?
    var legacy: [String: HistorySyncEnvelope] = [:]
    var loadFailures = 0, writeFailures = 0, loadCount = 0, writeCount = 0, legacyReadCount = 0
    var holdRead = false
    var holdWrite = false
    var beforeCommit: (() -> Void)?
    var metadataModes: [Bool] = []
    var readContinuation: CheckedContinuation<[String: HistorySyncEnvelope], Error>?
    var writeContinuation: CheckedContinuation<HistorySyncEnvelope, Error>?
    func scope(_ uid: String, _ profile: UUID) -> String { uid + ":" + profile.uuidString }
    func load(uid: String, profileID: UUID) async throws -> [String: HistorySyncEnvelope] {
        loadCount += 1
        if holdRead { return try await withCheckedThrowingContinuation { readContinuation = $0 } }
        if loadFailures > 0 { loadFailures -= 1; throw ProfileSyncError.unavailable }
        return documents[scope(uid, profileID)] ?? [:]
    }
    func commit(uid: String, profileID: UUID, id: String, record: HistorySyncEnvelope, importing: Bool, metadataOnly: Bool) async throws -> HistorySyncEnvelope {
        writeCount += 1
        metadataModes.append(metadataOnly)
        let prepare = beforeCommit; beforeCommit = nil; prepare?()
        if holdWrite { return try await withCheckedThrowingContinuation { writeContinuation = $0 } }
        if writeFailures > 0 { writeFailures -= 1; throw ProfileSyncError.unavailable }
        let key = scope(uid, profileID)
        var candidate = record
        if let current = documents[key]?[id] {
            if current == record || current.wins(over: record) || importing && current.protectsFromImport(record, id: id) || metadataOnly && current.deleted { return current }
            candidate = record.mergingKnownData(from: current, id: id, preservePlayback: metadataOnly)
        }
        documents[key, default: [:]][id] = candidate
        return candidate
    }
    func legacyTarget(uid: String, firstProfileID: UUID) async throws -> UUID {
        if target == nil { target = firstProfileID }; return target!
    }
    func legacyHistory(uid: String) async throws -> [String: HistorySyncEnvelope] { legacyReadCount += 1; return legacy }
    func listen(uid: String, profileID: UUID, receive: @escaping (Result<[String: HistorySyncEnvelope], Error>) -> Void) -> () -> Void {
        let key = scope(uid, profileID); listeners[key] = receive
        return { [weak self] in self?.listeners.removeValue(forKey: key) }
    }
}
