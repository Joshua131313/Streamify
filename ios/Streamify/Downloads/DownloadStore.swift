import Foundation
import Combine
import UIKit

enum DownloadStatus: String, Codable, Sendable { case downloading, completed, cancelled, failed }

struct CatalogDownloadDescriptor: Codable, Sendable {
    let id: Int
    let kind: String
    let title: String
    let season: Int
    let episode: Int
    let episodeTitle: String?
    var media: MediaItem? {
        guard id > 0, let kind = MediaKind(rawValue: kind), kind != .anime else { return nil }
        return MediaItem(id: id, kind: kind, title: title)
    }
}

struct DownloadItem: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var source: String?
    var fileName: String?
    let createdAt: Date
    var status: DownloadStatus
    var bytesWritten: Int64 = 0
    var expectedBytes: Int64 = 0
    var error: String?
    /// Persisted because URLSession task identifiers survive background relaunches.
    var taskIdentifier: Int?
    /// Optional fields preserve downloads saved before catalog downloads were added.
    var catalogKey: String? = nil
    var quality: Int? = nil
    var catalog: CatalogDownloadDescriptor? = nil
    /// Kept separately from expiring video links and optional for older metadata.
    var posterSource: String? = nil
    var posterFileName: String? = nil
    /// A moved URLSession file awaiting device compatibility checks. Persisted
    /// so a background relaunch can finish validation instead of losing it.
    var pendingFileName: String? = nil
    /// Persist the bound across background relaunches; manual Retry resets it.
    var automaticSourceRefreshes: Int? = nil
    var posterFileURL: URL? {
        guard let posterFileName, let directory = try? DownloadFiles.directory() else { return nil }
        return DownloadArtworkCache.fileURL(fileName: posterFileName, itemID: id, directory: directory)
    }
    func acceptsCallback(taskIdentifier: Int) -> Bool {
        status == .downloading && self.taskIdentifier == taskIdentifier
    }
    func acceptsValidation(taskIdentifier: Int, fileName: String) -> Bool {
        acceptsCallback(taskIdentifier: taskIdentifier) && pendingFileName == fileName
    }
    var progress: Double? { expectedBytes > 0 ? min(1, max(0, Double(bytesWritten) / Double(expectedBytes))) : nil }
    var fileURL: URL? {
        guard status == .completed, let fileName, !fileName.contains("/"), !fileName.contains("\\") else { return nil }
        return try? DownloadFiles.directory().appendingPathComponent(fileName)
    }
}

enum DownloadError: LocalizedError {
    case invalidURL, unsupportedFile, unsupportedMedia, invalidEpisode, alreadyDownloading, fileUnavailable, invalidResponse, rejected(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid direct HTTPS video address."
        case .unsupportedFile: return "Choose a direct MP4, M4V, or MOV video file."
        case .unsupportedMedia: return "Downloads are available for movies and TV episodes."
        case .invalidEpisode: return "Choose a valid season and episode before downloading."
        case .alreadyDownloading: return "This video is already downloading."
        case .fileUnavailable: return "The video file could not be opened."
        case .invalidResponse: return "This address returned a webpage instead of a video file."
        case .rejected(let code): return "The server could not download this video (HTTP \(code))."
        }
    }
}

enum DownloadFiles {
    static func directory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = root.appendingPathComponent("StreamifyDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }
    static func metadata() throws -> URL { try directory().appendingPathComponent("downloads.json") }
    static func isSupported(_ url: URL) -> Bool { ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) }
    static func manualURL(_ value: String) throws -> URL {
        guard let url = secureURL(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw DownloadError.invalidURL }
        guard isSupported(url) else { throw DownloadError.unsupportedFile }
        return url
    }
    /// Only the catalog resolver may supply signed URLs without a video suffix.
    static func resolvedURL(_ value: URL) throws -> URL {
        guard let url = secureURL(value.absoluteString) else { throw DownloadError.invalidURL }
        let suffix = url.pathExtension.lowercased()
        guard !["m3u8", "m3u", "mpd", "html", "htm", "json"].contains(suffix) else { throw DownloadError.unsupportedFile }
        return url
    }
    static func suffix(for url: URL?) -> String {
        guard let url, isSupported(url) else { return "mp4" }
        return url.pathExtension.lowercased()
    }
    /// Read only a small header; large video files stay on disk throughout validation.
    static func validateVideo(response: HTTPURLResponse, header: Data) throws {
        guard (200...299).contains(response.statusCode) else { throw DownloadError.rejected(response.statusCode) }
        let mime = response.mimeType?.lowercased() ?? ""
        guard !header.isEmpty, !mime.hasPrefix("text/"), !mime.contains("json"), !mime.contains("html"),
              !mime.contains("mpegurl"), !mime.contains("dash+xml") else { throw DownloadError.invalidResponse }
        let prefix = String(decoding: header.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))).lowercased()
        guard !prefix.hasPrefix("<"), !prefix.hasPrefix("{"), !prefix.hasPrefix("["), !prefix.hasPrefix("#extm3u") else {
            throw DownloadError.invalidResponse
        }
        let box = header.count >= 8 ? String(data: header.subdata(in: 4..<8), encoding: .ascii) : nil
        let isVideoHeader = ["ftyp", "moov", "mdat", "wide", "free", "skip", "pnot"].contains(box ?? "")
        let isVideoMIME = mime.hasPrefix("video/") || ["application/octet-stream", "binary/octet-stream", "application/mp4", ""].contains(mime)
        guard isVideoMIME && isVideoHeader else {
            throw DownloadError.invalidResponse
        }
    }
    static func importVideo(_ url: URL) async throws -> DownloadItem {
        guard isSupported(url) else { throw DownloadError.unsupportedFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let fileName = "\(id.uuidString).\(url.pathExtension.lowercased())"
        let destination = try directory().appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            _ = try await OfflineVideoValidation.validate(destination)
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return DownloadItem(id: id, title: url.deletingPathExtension().lastPathComponent, source: nil, fileName: fileName,
                                createdAt: Date(), status: .completed, bytesWritten: size, expectedBytes: size)
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    static func pendingURL(fileName: String, id: UUID) throws -> URL? {
        guard fileName.hasPrefix("pending-\(id.uuidString)-"), !fileName.contains("/"), !fileName.contains("\\"),
              ["mp4", "m4v", "mov"].contains(URL(fileURLWithPath: fileName).pathExtension.lowercased()) else { return nil }
        return try directory().appendingPathComponent(fileName)
    }
}

/// One shared owner keeps background URLSession delegates alive across every screen.
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()
    static let sessionIdentifier = (Bundle.main.bundleIdentifier ?? "com.streamify.ios") + ".downloads.v1"
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var storageError: String?
    var backgroundCompletion: (() -> Void)? {
        didSet { if backgroundCompletion != nil { backgroundEventsFinished = false } }
    }
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var resolutions: [UUID: Task<Void, Never>] = [:]
    private var resolutionAttempts: [UUID: UUID] = [:]
    private var artworkTasks: [UUID: Task<Void, Never>] = [:]
    private var artworkAttempts: [UUID: UUID] = [:]
    private var validations: [UUID: Task<Void, Never>] = [:]
    private var validationAttempts: [UUID: UUID] = [:]
    private var backgroundEventsFinished = false
    private var lastSave = Date.distantPast
    private lazy var delegate = DownloadSessionDelegate(owner: self)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    private init() {
        var restoredMetadata = false
        do {
            let url = try DownloadFiles.metadata()
            if FileManager.default.fileExists(atPath: url.path) {
                items = try JSONDecoder().decode([DownloadItem].self, from: Data(contentsOf: url))
                restoredMetadata = true
                for index in items.indices where items[index].status == .completed {
                    if let file = items[index].fileURL, !FileManager.default.fileExists(atPath: file.path) {
                        items[index].status = .failed
                        items[index].error = "The local file is missing. Download or import it again."
                    }
                }
            }
        } catch { storageError = "Saved downloads could not be read. \(error.localizedDescription)" }
        // Missing/corrupt metadata must never cause existing movie files to be
        // deleted merely because their retained filenames cannot be recovered.
        if restoredMetadata { removeOrphanedPendingFiles() }
        reconnectTasks()
    }

    func add(url value: String, title: String = "") throws {
        let url = try DownloadFiles.manualURL(value)
        guard !items.contains(where: { $0.source == url.absoluteString && $0.status == .downloading }) else { throw DownloadError.alreadyDownloading }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = DownloadItem(id: UUID(), title: name.isEmpty ? url.deletingPathExtension().lastPathComponent : String(name.prefix(160)), source: url.absoluteString,
                                createdAt: Date(), status: .downloading)
        items.insert(item, at: 0)
        start(item)
        save()
    }

    nonisolated static func catalogKey(media: MediaItem, season: Int = 1, episode: Int = 1) -> String {
        switch media.kind {
        case .movie: return "movie:\(media.id)"
        case .tv: return "tv:\(media.id):\(season):\(episode)"
        case .anime: return "anime:\(media.id)"
        }
    }

    func item(media: MediaItem, season: Int = 1, episode: Int = 1) -> DownloadItem? {
        let key = Self.catalogKey(media: media, season: season, episode: episode)
        return items.first { $0.catalogKey == key }
    }

    @discardableResult
    func add(resolved: ResolvedMediaDownload, media: MediaItem, season: Int = 1, episode: Int = 1, episodeTitle: String? = nil, replacingDownloadID: UUID? = nil) throws -> UUID {
        guard media.kind != .anime, media.id > 0 else { throw DownloadError.unsupportedMedia }
        guard media.kind == .movie || season > 0 && episode > 0 else { throw DownloadError.invalidEpisode }
        let key = Self.catalogKey(media: media, season: season, episode: episode)
        let existing = items.first(where: { $0.catalogKey == key })
        if let replacingDownloadID, existing?.id != replacingDownloadID { throw DownloadError.fileUnavailable }
        if let existing, existing.status == .downloading || existing.status == .completed && replacingDownloadID != existing.id {
            return existing.id
        }
        let url = try DownloadFiles.resolvedURL(resolved.url)
        let descriptor = CatalogDownloadDescriptor(id: media.id, kind: media.kind.rawValue, title: media.title,
            season: season, episode: episode, episodeTitle: episodeTitle)
        let episodeName = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = media.kind == .movie ? media.title : "\(media.title) · S\(season) E\(episode)" + (episodeName.isEmpty ? "" : " · \(episodeName)")
        let posterSource = (media.backdropURL ?? media.posterURL)?.absoluteString
        let id: UUID
        if let index = items.firstIndex(where: { $0.catalogKey == key }) {
            id = items[index].id
            cancelValidation(id: id)
            tasks[id]?.cancel()
            tasks[id] = nil
            resolutions[id]?.cancel()
            resolutions[id] = nil
            resolutionAttempts[id] = nil
            // Signed addresses expire; replace the URL instead of retrying the old token.
            items[index].source = url.absoluteString
            items[index].title = String(title.prefix(240))
            items[index].quality = resolved.quality
            items[index].catalog = descriptor
            if items[index].posterSource != posterSource { clearArtwork(id: id) }
            items[index].posterSource = posterSource
            items[index].status = .downloading
            items[index].taskIdentifier = nil
            items[index].bytesWritten = 0
            items[index].expectedBytes = 0
            items[index].error = nil
            start(items[index])
        } else {
            id = UUID()
            let download = DownloadItem(id: id, title: String(title.prefix(240)), source: url.absoluteString,
                                        createdAt: Date(), status: .downloading, catalogKey: key, quality: resolved.quality, catalog: descriptor, posterSource: posterSource)
            items.insert(download, at: 0)
            start(download)
        }
        cacheArtwork(id: id)
        save()
        return id
    }

    func cancel(id: UUID) {
        defer { finishBackgroundEventsIfPossible() }
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].status == .downloading else { return }
        cancelValidation(id: id)
        // The cancelled row remains available for Retry. Keep its saved poster
        // and any artwork fetch; deleting the row removes that artwork instead.
        resolutions[id]?.cancel()
        resolutions[id] = nil
        resolutionAttempts[id] = nil
        tasks[id]?.cancel()
        tasks[id] = nil
        items[index].status = .cancelled
        items[index].taskIdentifier = nil
        items[index].error = nil
        save()
    }

    func retry(id: UUID) {
        retry(id: id, refreshingExpiredSource: false)
    }

    private func retry(id: UUID, refreshingExpiredSource: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status == .failed || items[index].status == .cancelled,
              items[index].source.flatMap(secureURL) != nil else { return }
        let failedSource = items[index].source
        let failureMessage = items[index].error
        if refreshingExpiredSource {
            guard (items[index].automaticSourceRefreshes ?? 0) < 1 else { return }
            items[index].automaticSourceRefreshes = 1
        } else { items[index].automaticSourceRefreshes = 0 }
        cancelValidation(id: id)
        items[index].status = .downloading
        items[index].bytesWritten = 0
        items[index].expectedBytes = 0
        items[index].error = nil
        cacheArtwork(id: id)
        if let descriptor = items[index].catalog, let media = descriptor.media {
            // Resolve again on Retry: a saved CDN address may have expired.
            let attempt = UUID()
            let quality = items[index].quality ?? 1080
            resolutionAttempts[id] = attempt
            items[index].taskIdentifier = nil
            resolutions[id] = Task { @MainActor [weak self] in
                defer {
                    if self?.resolutionAttempts[id] == attempt {
                        self?.resolutionAttempts[id] = nil
                        self?.resolutions[id] = nil
                    }
                    self?.finishBackgroundEventsIfPossible()
                }
                do {
                    let resolved = try await MediaDownloadResolver().resolve(media: media, season: descriptor.season,
                        episode: descriptor.episode, maximumQuality: quality)
                    try Task.checkCancellation()
                    guard let self, self.resolutionAttempts[id] == attempt,
                          let current = self.items.firstIndex(where: { $0.id == id }), self.items[current].status == .downloading else { return }
                    guard !refreshingExpiredSource || resolved.url.absoluteString != failedSource else {
                        self.items[current].status = .failed
                        self.items[current].error = failureMessage ?? "This download source is unavailable. Try again later or choose another quality."
                        self.save()
                        return
                    }
                    self.items[current].source = resolved.url.absoluteString
                    self.items[current].quality = resolved.quality
                    self.start(self.items[current]); self.save()
                } catch is CancellationError { }
                catch {
                    guard let self, self.resolutionAttempts[id] == attempt,
                          let current = self.items.firstIndex(where: { $0.id == id }), self.items[current].status == .downloading else { return }
                    self.items[current].status = .failed
                    self.items[current].error = error.localizedDescription
                    self.save()
                }
            }
            save()
            return
        }
        start(items[index])
        save()
    }

    func remove(id: UUID) {
        defer { finishBackgroundEventsIfPossible() }
        cancelValidation(id: id)
        clearArtwork(id: id)
        resolutions[id]?.cancel()
        resolutions[id] = nil
        resolutionAttempts[id] = nil
        tasks[id]?.cancel()
        tasks[id] = nil
        if let item = items.first(where: { $0.id == id }), let fileName = item.fileName,
           !fileName.contains("/"), !fileName.contains("\\"), let directory = try? DownloadFiles.directory() {
            let file = directory.appendingPathComponent(fileName)
            do { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
            catch { storageError = "The local file could not be removed. \(error.localizedDescription)"; return }
        }
        if let directory = try? DownloadFiles.directory() {
            let captions = directory.appendingPathComponent("captions-\(id.uuidString).txt")
            try? FileManager.default.removeItem(at: captions)
        }
        UserDefaults.standard.removeObject(forKey: "streamify.ios.offlineSubtitles.\(id.uuidString)")
        items.removeAll { $0.id == id }
        save()
    }

    func importFile(url: URL) async throws {
        let copy = Task.detached(priority: .userInitiated) { try await DownloadFiles.importVideo(url) }
        let item = try await withTaskCancellationHandler { try await copy.value } onCancel: { copy.cancel() }
        if Task.isCancelled {
            if let file = item.fileURL { try? FileManager.default.removeItem(at: file) }
            throw CancellationError()
        }
        items.insert(item, at: 0)
        save()
    }

    #if DEBUG
    func installCompletedFixture(_ item: DownloadItem) {
        guard PreviewFixtures.enabled, item.status == .completed else { return }
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        save()
    }
    func installDownloadStatusFixtures(_ fixtures: [DownloadItem]) {
        guard PreviewFixtures.enabled else { return }
        items.removeAll { PreviewFixtures.downloadStatusIDs.contains($0.id) }
        items.insert(contentsOf: fixtures, at: 0)
        save()
    }
    #endif

    /// Existing identified catalog downloads can recover artwork without delaying playback.
    /// Imports and direct links never guess a title's identity from its filename.
    func refreshArtwork(token: String) {
        for item in items where item.status != .cancelled { cacheArtwork(id: item.id, token: token) }
    }

    private func cacheArtwork(id: UUID, token: String = "") {
        guard artworkTasks[id] == nil, let item = items.first(where: { $0.id == id }), item.status != .cancelled else { return }
        if let file = item.posterFileURL, FileManager.default.fileExists(atPath: file.path) { return }
        guard item.posterSource.flatMap(secureURL) != nil || (item.catalog?.media != nil && !token.isEmpty) else { return }
        let attempt = UUID()
        artworkAttempts[id] = attempt
        artworkTasks[id] = Task { @MainActor [weak self] in
            defer {
                if self?.artworkAttempts[id] == attempt {
                    self?.artworkAttempts[id] = nil
                    self?.artworkTasks[id] = nil
                }
            }
            do {
                var source = item.posterSource.flatMap(secureURL)
                if source == nil, let media = item.catalog?.media {
                    let details = try await TMDBClient(token: token).details(media)
                    guard details.media.id == media.id, details.media.kind == media.kind else { return }
                    source = details.media.backdropURL ?? details.media.posterURL
                }
                guard let source else { return }
                let jpeg = try await DownloadArtworkCache.fetch(source)
                try Task.checkCancellation()
                guard let self, self.artworkAttempts[id] == attempt,
                      let index = self.items.firstIndex(where: { $0.id == id }), self.items[index].status != .cancelled,
                      self.items[index].posterSource == item.posterSource else { return }
                let name = "\(id.uuidString)-artwork-\(attempt.uuidString).jpg"
                let directory = try DownloadFiles.directory()
                guard let destination = DownloadArtworkCache.fileURL(fileName: name, itemID: id, directory: directory) else { return }
                try jpeg.write(to: destination, options: .atomic)
                if let old = self.items[index].posterFileName { try? DownloadArtworkCache.remove(fileName: old, itemID: id, directory: directory) }
                self.items[index].posterSource = source.absoluteString
                self.items[index].posterFileName = name
                self.save()
            } catch { /* Artwork availability never fails an otherwise valid download. */ }
        }
    }

    private func clearArtwork(id: UUID) {
        artworkTasks[id]?.cancel()
        artworkTasks[id] = nil
        artworkAttempts[id] = nil
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let name = items[index].posterFileName, let directory = try? DownloadFiles.directory() {
            try? DownloadArtworkCache.remove(fileName: name, itemID: id, directory: directory)
        }
        items[index].posterFileName = nil
    }

    func reconnectTasks() {
        for item in items where item.status == .downloading {
            if let pending = item.pendingFileName, let taskIdentifier = item.taskIdentifier, validations[item.id] == nil {
                validatePending(id: item.id, taskIdentifier: taskIdentifier, fileName: pending)
            }
        }
        session.getAllTasks { [weak self] restored in
            Task { @MainActor in
                guard let self else { return }
                var active = Set<UUID>()
                #if DEBUG
                if PreviewFixtures.usesDownloadStatus { active.formUnion(PreviewFixtures.downloadStatusIDs) }
                #endif
                for task in restored.sorted(by: { $0.taskIdentifier > $1.taskIdentifier }) {
                    guard let download = task as? URLSessionDownloadTask, let description = download.taskDescription,
                          let id = UUID(uuidString: description), let index = self.items.firstIndex(where: { $0.id == id }),
                          self.items[index].status == .downloading,
                          self.items[index].pendingFileName == nil,
                          self.items[index].taskIdentifier == nil || self.items[index].taskIdentifier == download.taskIdentifier,
                          self.tasks[id] == nil || self.tasks[id]?.taskIdentifier == download.taskIdentifier
                    else { task.cancel(); continue }
                    active.insert(id)
                    self.tasks[id] = download
                    self.items[index].taskIdentifier = download.taskIdentifier
                    if task.state == .suspended { task.resume() }
                }
                for index in self.items.indices where self.items[index].status == .downloading && !active.contains(self.items[index].id) && self.tasks[self.items[index].id] == nil && self.resolutions[self.items[index].id] == nil && self.validations[self.items[index].id] == nil {
                    self.items[index].status = .failed
                    self.items[index].error = "The download was interrupted. Tap Retry to start again."
                }
                self.save()
            }
        }
    }

    fileprivate func update(id: UUID, taskIdentifier: Int, written: Int64, expected: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].acceptsCallback(taskIdentifier: taskIdentifier) else { return }
        items[index].bytesWritten = written
        items[index].expectedBytes = max(0, expected)
        if Date().timeIntervalSince(lastSave) > 3 { save() }
    }

    fileprivate func received(id: UUID, taskIdentifier: Int, fileName: String, size: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].acceptsCallback(taskIdentifier: taskIdentifier) else {
            removePendingFile(fileName, id: id)
            return
        }
        if let current = items[index].pendingFileName {
            if current != fileName { removePendingFile(fileName, id: id) }
            return
        }
        tasks[id] = nil
        items[index].pendingFileName = fileName
        items[index].bytesWritten = size
        items[index].expectedBytes = size
        items[index].error = nil
        save()
        validatePending(id: id, taskIdentifier: taskIdentifier, fileName: fileName)
    }

    fileprivate func failed(id: UUID, taskIdentifier: Int, message: String, expiredSource: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].acceptsCallback(taskIdentifier: taskIdentifier) else { return }
        cancelValidation(id: id)
        tasks[id] = nil
        items[index].status = .failed
        items[index].taskIdentifier = nil
        items[index].error = message
        save()
        if expiredSource, items[index].catalog?.media != nil,
           (items[index].automaticSourceRefreshes ?? 0) < 1 {
            retry(id: id, refreshingExpiredSource: true)
        }
    }

    private func validatePending(id: UUID, taskIdentifier: Int, fileName: String) {
        guard validations[id] == nil else { return }
        let attempt = UUID()
        validationAttempts[id] = attempt
        validations[id] = Task { @MainActor [weak self] in
            defer {
                if self?.validationAttempts[id] == attempt {
                    self?.validationAttempts[id] = nil; self?.validations[id] = nil
                    self?.finishBackgroundEventsIfPossible()
                }
            }
            do {
                guard let url = try DownloadFiles.pendingURL(fileName: fileName, id: id) else { throw OfflineVideoError.missingFile }
                _ = try await OfflineVideoValidation.validate(url)
                try Task.checkCancellation()
                guard let self, self.validationAttempts[id] == attempt,
                      let index = self.items.firstIndex(where: { $0.id == id }),
                      self.items[index].acceptsValidation(taskIdentifier: taskIdentifier, fileName: fileName) else { return }
                let oldFileName = self.items[index].fileName
                self.items[index].fileName = fileName
                self.items[index].pendingFileName = nil
                self.items[index].status = .completed
                self.items[index].taskIdentifier = nil
                self.items[index].error = nil
                self.cacheArtwork(id: id); self.save()
                // A failed/cancelled replacement never deletes the previous
                // file. Only remove it after the new playable file is saved.
                if self.storageError == nil, let oldFileName, oldFileName != fileName,
                   !oldFileName.contains("/"), !oldFileName.contains("\\"),
                   let directory = try? DownloadFiles.directory() {
                    let old = directory.appendingPathComponent(oldFileName)
                    if DownloadFiles.isSupported(old) { try? FileManager.default.removeItem(at: old) }
                }
            } catch {
                guard let self, self.validationAttempts[id] == attempt,
                      let index = self.items.firstIndex(where: { $0.id == id }),
                      self.items[index].acceptsValidation(taskIdentifier: taskIdentifier, fileName: fileName) else { return }
                self.removePendingFile(fileName, id: id)
                self.items[index].pendingFileName = nil
                self.items[index].status = .failed
                self.items[index].taskIdentifier = nil
                self.items[index].error = OfflineVideoError.classify(error).downloadMessage
                self.save()
            }
        }
    }

    private func cancelValidation(id: UUID) {
        validationAttempts[id] = nil
        validations[id]?.cancel(); validations[id] = nil
        if let index = items.firstIndex(where: { $0.id == id }), let fileName = items[index].pendingFileName {
            removePendingFile(fileName, id: id)
            items[index].pendingFileName = nil
        }
        finishBackgroundEventsIfPossible()
    }

    private func removePendingFile(_ fileName: String, id: UUID) {
        if let url = try? DownloadFiles.pendingURL(fileName: fileName, id: id) { try? FileManager.default.removeItem(at: url) }
    }

    private func removeOrphanedPendingFiles() {
        guard let directory = try? DownloadFiles.directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let retained = Set(items.flatMap { [$0.fileName, $0.pendingFileName].compactMap { $0 } })
        for url in files where url.lastPathComponent.hasPrefix("pending-") && !retained.contains(url.lastPathComponent) {
            // Only this version's generated pending video names are eligible.
            let parts = url.lastPathComponent.dropFirst("pending-".count)
            guard parts.count > 36, UUID(uuidString: String(parts.prefix(36))) != nil, DownloadFiles.isSupported(url) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    fileprivate func didFinishBackgroundEvents() {
        backgroundEventsFinished = true
        finishBackgroundEventsIfPossible()
    }
    fileprivate func finishBackgroundEventsIfPossible() {
        guard backgroundEventsFinished, validations.isEmpty, resolutions.isEmpty, !delegate.hasPendingOwnerCallbacks,
              let completion = backgroundCompletion else { return }
        backgroundEventsFinished = false; backgroundCompletion = nil
        completion()
    }

    private func start(_ item: DownloadItem) {
        guard let source = item.source, let url = secureURL(source) else { return }
        var request = URLRequest(url: url)
        request.setValue("video/*, application/octet-stream", forHTTPHeaderField: "Accept")
        let task = session.downloadTask(with: request)
        task.taskDescription = item.id.uuidString
        tasks[item.id] = task
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].taskIdentifier = task.taskIdentifier }
        task.resume()
    }

    private func save() {
        do { try JSONEncoder().encode(items).write(to: DownloadFiles.metadata(), options: .atomic); lastSave = Date(); storageError = nil }
        catch { storageError = "Download metadata could not be saved. \(error.localizedDescription)" }
    }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: DownloadStore?
    private let callbackLock = NSLock()
    private var pendingOwnerCallbacks = 0
    init(owner: DownloadStore) { self.owner = owner }
    private func id(_ task: URLSessionTask) -> UUID? { task.taskDescription.flatMap(UUID.init(uuidString:)) }
    var hasPendingOwnerCallbacks: Bool {
        callbackLock.lock(); defer { callbackLock.unlock() }
        return pendingOwnerCallbacks > 0
    }
    private func beginOwnerCallback() {
        callbackLock.lock(); defer { callbackLock.unlock() }; pendingOwnerCallbacks += 1
    }
    private func endOwnerCallback() {
        callbackLock.lock(); defer { callbackLock.unlock() }; pendingOwnerCallbacks -= 1
    }
    /// Count before hopping actors. Task scheduling order is not a guarantee:
    /// the background-events callback may arrive on the main actor first.
    private func deliver(_ action: @escaping @MainActor (DownloadStore?) -> Void) {
        beginOwnerCallback()
        Task { @MainActor [weak self] in
            guard let self else { return }
            action(self.owner)
            self.endOwnerCallback()
            self.owner?.finishBackgroundEventsIfPossible()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = id(downloadTask) else { return }
        let taskIdentifier = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in self?.owner?.update(id: id, taskIdentifier: taskIdentifier, written: totalBytesWritten, expected: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = id(downloadTask) else { return }
        let taskIdentifier = downloadTask.taskIdentifier
        var movedFile: URL?
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else { throw DownloadError.invalidResponse }
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 1024) ?? Data()
            try DownloadFiles.validateVideo(response: response, header: header)
            let suffix = DownloadFiles.suffix(for: downloadTask.originalRequest?.url)
            let fileName = "pending-\(id.uuidString)-\(taskIdentifier)-\(UUID().uuidString).\(suffix)"
            let destination = try DownloadFiles.directory().appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            // Temporary URLSession files must be moved before this delegate returns.
            try FileManager.default.moveItem(at: location, to: destination)
            movedFile = destination
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            deliver { owner in
                if let owner { owner.received(id: id, taskIdentifier: taskIdentifier, fileName: fileName, size: size) }
                else { try? FileManager.default.removeItem(at: destination) }
            }
        } catch {
            if let movedFile { try? FileManager.default.removeItem(at: movedFile) }
            let message = error.localizedDescription
            let expiredSource = (downloadTask.response as? HTTPURLResponse).map { [403, 404, 410].contains($0.statusCode) } ?? false
            deliver { $0?.failed(id: id, taskIdentifier: taskIdentifier, message: message, expiredSource: expiredSource) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled, let id = id(task) else { return }
        let taskIdentifier = task.taskIdentifier
        let message = error.localizedDescription
        deliver { $0?.failed(id: id, taskIdentifier: taskIdentifier, message: message) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let address = request.url?.absoluteString, secureURL(address) != nil else { completionHandler(nil); return }
        completionHandler(request)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        deliver { $0?.didFinishBackgroundEvents() }
    }
}

/// Wire with @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) in StreamifyApp.
@MainActor
final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication { configuration.delegateClass = AppQuickActionSceneDelegate.self }
        return configuration
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadStore.sessionIdentifier else { completionHandler(); return }
        DownloadStore.shared.backgroundCompletion = completionHandler
        DownloadStore.shared.reconnectTasks()
    }
}
