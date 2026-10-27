import Foundation

struct ResolvedMediaDownload: Sendable {
    let url: URL
    let quality: Int
    var headers: [String: String] = [:]
    var expiresAt: Date? = nil
    var codec: String? = nil
    var requiresProxy: Bool = false
    var sourceID: String? = nil
    var actualWidth: Int? = nil
    var actualHeight: Int? = nil
    var actualCodecs: [String]? = nil

    var needsRefresh: Bool { expiresAt.map { $0.timeIntervalSinceNow < 30 } ?? false }
}

enum MediaDownloadResolutionError: LocalizedError, Equatable {
    case unsupportedMedia
    case invalidEpisode
    case unavailable
    case invalidResponse
    case streamingOnly
    case qualityUnavailable
    case unsafeSource
    case incompatibleSource

    var errorDescription: String? {
        switch self {
        case .unsupportedMedia:
            return "Downloads are available for movies and TV episodes. Choose a movie or show from the catalog."
        case .invalidEpisode:
            return "Choose a season and episode before downloading this show."
        case .unavailable:
            return "The download source is unavailable. Please try again later."
        case .invalidResponse:
            return "The download source returned an unreadable response. Please try again later."
        case .streamingOnly:
            return "This title is available for streaming only; no video file is available to download."
        case .qualityUnavailable:
            return "No download is available at the selected quality. Choose another resolution and try again."
        case .unsafeSource:
            return "The source did not provide a supported HTTPS video file. Try streaming this title instead."
        case .incompatibleSource:
            return "The selected quality cannot be played by this iPhone. Choose another quality or watch online."
        }
    }
}

/// Resolves the same movie/TV file source used by the Android download flow.
/// Metadata requests are bounded; embedded players, playlists, and DRM are never downloaded.
struct MediaDownloadResolver {
    private let session: URLSession
    private let sourceValidator: (@Sendable (URL) async throws -> Void)?

    init(session: URLSession = .shared,
         sourceValidator: (@Sendable (URL) async throws -> Void)? = nil) {
        self.session = session
        self.sourceValidator = sourceValidator
    }

    func resolve(media: MediaItem, season: Int = 1, episode: Int = 1,
                 maximumQuality: Int = 1080, excludingSources: Set<String> = []) async throws -> ResolvedMediaDownload {
        try Task.checkCancellation()
        guard media.id > 0, media.kind == .movie || media.kind == .tv else {
            throw MediaDownloadResolutionError.unsupportedMedia
        }
        guard media.kind != .tv || (season > 0 && episode > 0) else {
            throw MediaDownloadResolutionError.invalidEpisode
        }
        // The quality picker is an exact choice. Compatibility checks must not
        // silently turn a selected 1080p download into a different resolution.
        let qualities = [1080, 720, 480, 360].filter { $0 == maximumQuality }
        guard !qualities.isEmpty else { throw MediaDownloadResolutionError.qualityUnavailable }

        var tokenAddress = URLComponents()
        tokenAddress.scheme = "https"
        tokenAddress.host = "enc-dec.app"
        tokenAddress.path = "/api/enc-vidlink"
        tokenAddress.queryItems = [URLQueryItem(name: "text", value: String(media.id))]
        guard let tokenURL = tokenAddress.url else { throw MediaDownloadResolutionError.invalidResponse }
        let tokenObject = try await object(at: tokenURL, maximumBytes: 32 * 1024)
        guard let token = tokenObject["result"] as? String, !token.isEmpty, token.utf8.count <= 4096,
              token.unicodeScalars.allSatisfy({ Self.tokenCharacters.contains($0) }),
              let escapedToken = token.addingPercentEncoding(withAllowedCharacters: Self.pathComponentCharacters) else {
            throw MediaDownloadResolutionError.invalidResponse
        }

        var address = URLComponents()
        address.scheme = "https"
        address.host = "vidlink.pro"
        address.percentEncodedPath = media.kind == .movie
            ? "/api/b/movie/\(escapedToken)"
            : "/api/b/tv/\(escapedToken)/\(season)/\(episode)"
        guard let sourceURL = address.url, sourceURL.host == "vidlink.pro", sourceURL.fragment == nil else {
            throw MediaDownloadResolutionError.invalidResponse
        }
        let sourceObject = try await object(at: sourceURL, provider: true, maximumBytes: 512 * 1024)
        guard let stream = sourceObject["stream"] as? [String: Any] else {
            throw MediaDownloadResolutionError.unavailable
        }
        guard stream["type"] as? String == "file", !Self.hasDRM(stream) else {
            throw MediaDownloadResolutionError.streamingOnly
        }
        guard let available = stream["qualities"] as? [String: Any] else {
            throw MediaDownloadResolutionError.qualityUnavailable
        }

        var foundAddress = false
        var foundPlaylist = false
        var foundIncompatibleSource = false
        var sourceFailure: Error?
        var checkedSources = Set<URL>()
        for quality in qualities {
            // Only URLs actually returned for the exact selected quality are
            // candidates. Never synthesize a CDN URL or inspect lower tiers.
            let entries = (available[String(quality)] as? [[String: Any]])
                ?? (available[String(quality)] as? [String: Any]).map { [$0] } ?? []
            for item in entries.prefix(4) {
                guard let value = item["url"] as? String, !value.isEmpty else { continue }
                foundAddress = true
                guard !Self.hasDRM(item), let url = Self.videoFileURL(value) else {
                    let fileExtension = URLComponents(string: value)?.url?.pathExtension.lowercased()
                    foundPlaylist = foundPlaylist || fileExtension == "m3u8" || fileExtension == "mpd" || Self.hasDRM(item)
                    continue
                }
                try Task.checkCancellation()
                // Some quality entries point at the same physical file. Do not
                // inspect an already rejected source again and amplify rate limits.
                guard checkedSources.insert(url).inserted else { continue }
                guard !excludingSources.contains(url.absoluteString) else { foundIncompatibleSource = true; continue }
                var candidate = ResolvedMediaDownload(url: url, quality: quality,
                    headers: DownloadSourceHeaders.sanitized(item["headers"] as? [String: String] ?? [:]),
                    expiresAt: Self.expiry(item: item, stream: stream), codec: item["codecName"] as? String,
                    requiresProxy: item["requiresProxy"] as? Bool ?? false, sourceID: sourceObject["sourceId"] as? String)
                do {
                    if let sourceValidator { try await sourceValidator(url) }
                    else {
                        let metadata = try await DownloadSourceProbe(session: session).inspect(candidate)
                        try OfflineVideoValidation.requireQuality(quality, width: metadata.width, height: metadata.height)
                        candidate.actualWidth = metadata.width
                        candidate.actualHeight = metadata.height
                        candidate.actualCodecs = metadata.codecs
                        // AVURLAsset has no public arbitrary-header configuration.
                        // Header-dependent files get the same URLSession probe and
                        // the real, local AVFoundation check after transfer.
                        if candidate.headers.isEmpty { try await OfflineVideoValidation.validateRemoteSource(url) }
                    }
                    try Task.checkCancellation()
                } catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    if let error = error as? OfflineVideoError, error.isCompatibilityIssue {
                        foundIncompatibleSource = true
                        continue
                    }
                    if let failure = error as? DownloadSourceProbeError {
                        if failure.stopsFallback { throw failure }
                        sourceFailure = failure
                        continue
                    }
                    if let failure = error as? OfflineVideoError, failure == .qualityMismatch {
                        sourceFailure = failure
                        continue
                    }
                    // A transport error is neither a codec verdict nor a reason
                    // to hammer the source with a second request.
                    throw MediaDownloadResolutionError.unavailable
                }
                return candidate
            }
        }
        if let sourceFailure { throw sourceFailure }
        if foundIncompatibleSource { throw MediaDownloadResolutionError.incompatibleSource }
        if foundPlaylist { throw MediaDownloadResolutionError.streamingOnly }
        throw foundAddress ? MediaDownloadResolutionError.unsafeSource : MediaDownloadResolutionError.qualityUnavailable
    }

    private static let tokenCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/_=-")
    private static let pathComponentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    private static func expiry(item: [String: Any], stream: [String: Any], now: Date = Date()) -> Date? {
        if let seconds = item["expiresAt"] as? NSNumber, seconds.doubleValue > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds.doubleValue)
        }
        guard let ttl = (item["TTL"] ?? stream["TTL"]) as? NSNumber, ttl.doubleValue.isFinite else { return nil }
        return now.addingTimeInterval(min(max(0, ttl.doubleValue), 86_400))
    }

    private static func videoFileURL(_ value: String) -> URL? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.port == nil || parts.port == 443,
              let url = parts.url, ["", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    private static func hasDRM(_ object: [String: Any]) -> Bool {
        ["drm", "drmInfo", "license", "licenseUrl", "licenseURL"].contains { key in
            guard let value = object[key], !(value is NSNull) else { return false }
            if let boolean = value as? Bool { return boolean }
            if let string = value as? String { return !string.isEmpty && string.lowercased() != "false" }
            if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
            return true
        }
    }

    private func object(at url: URL, provider: Bool = false, maximumBytes: Int) async throws -> [String: Any] {
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider {
            request.setValue("https://vidlink.pro", forHTTPHeaderField: "Origin")
            request.setValue("https://vidlink.pro/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: DownloadMetadataRedirectPolicy())
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", http.url?.host == url.host,
                  http.url?.user == nil, http.url?.password == nil, http.url?.fragment == nil else {
                throw MediaDownloadResolutionError.unavailable
            }
            guard response.expectedContentLength <= Int64(maximumBytes) else {
                throw MediaDownloadResolutionError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw MediaDownloadResolutionError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MediaDownloadResolutionError.invalidResponse
            }
            return result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if error is MediaDownloadResolutionError { throw error }
            throw MediaDownloadResolutionError.unavailable
        }
    }
}

/// These are canonical API endpoints. Refuse redirects rather than forwarding provider headers elsewhere.
private final class DownloadMetadataRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Only non-secret request context may travel with a public download address.
/// Range and transport headers are controlled by our downloader, not metadata.
enum DownloadSourceHeaders {
    static func sanitized(_ headers: [String: String]) -> [String: String] {
        let names = ["referer": "Referer", "origin": "Origin", "user-agent": "User-Agent",
                     "accept": "Accept", "accept-language": "Accept-Language"]
        var result: [String: String] = [:]
        for (key, value) in headers {
            guard let name = names[key.lowercased()], !value.isEmpty, value.utf8.count <= 2048,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
            if name == "Referer" || name == "Origin" {
                guard let url = URLComponents(string: value), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil, url.fragment == nil else { continue }
            }
            result[name] = value
        }
        return result
    }

    static func request(url: URL, headers: [String: String], timeout: TimeInterval = 60) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        request.setValue("video/*, application/octet-stream", forHTTPHeaderField: "Accept")
        for (name, value) in sanitized(headers) { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    static func redirected(_ request: URLRequest, from original: URL?) -> URLRequest? {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.port == nil || parts.port == 443 else { return nil }
        var next = request
        // Never forward cookies, authorization, or provider-specific context to
        // a new origin. A provider must advertise a usable direct file URL.
        if original?.host?.lowercased() != url.host?.lowercased() || original?.port != url.port {
            for name in ["Authorization", "Cookie", "Referer", "Origin"] { next.setValue(nil, forHTTPHeaderField: name) }
        }
        return next
    }
}

enum DownloadSourceProbeError: LocalizedError {
    case rejected(Int), invalidVideo, metadataUnavailable, changedSource
    var errorDescription: String? {
        switch self {
        case .rejected(let status):
            return status == 429 ? "The download server is busy (HTTP 429). Please wait before trying again."
                : "The download server refused this file (HTTP \(status)). Try again to request a fresh source."
        case .invalidVideo: return "The download source returned a webpage or playlist instead of a video file."
        case .metadataUnavailable: return "The download server could not provide readable video metadata. Try another source or try again later."
        case .changedSource: return "The download source changed while it was being checked. Please try again for a fresh address."
        }
    }
    var stopsFallback: Bool {
        if case .rejected(let status) = self { return status == 429 || status >= 500 }
        return false
    }
}

/// Reads only the MP4 header and bounded movie metadata, never an entire film.
/// This uses public URLSession request headers. AVFoundation inspects the full
/// local file after transfer, so a bare-URL authentication/transport failure
/// cannot be mistaken for an unsupported codec on header-dependent sources.
struct DownloadSourceProbe {
    let session: URLSession
    struct Metadata: Equatable {
        let width: Int
        let height: Int
        let codecs: [String]
    }
    private struct Slice { let data: Data; let offset: Int64; let total: Int64?; let etag: String? }
    private struct Box { let offset: Int; let size: Int64; let kind: String; let header: Int }

    func inspect(_ source: ResolvedMediaDownload) async throws -> Metadata {
        try Task.checkCancellation()
        let first = try await read(source, offset: 0, length: 64 * 1024)
        var offset: Int64 = 0
        for _ in 0..<24 {
            try Task.checkCancellation()
            if let total = first.total, offset >= total { break }
            let part: Slice
            if offset < Int64(first.data.count) { part = first }
            else { part = try await read(source, offset: offset, length: 16, matching: first) }
            let position = Int(offset - part.offset)
            guard let box = Self.box(part.data, at: position), box.size > 0,
                  box.size <= Int64.max - offset else { throw DownloadSourceProbeError.metadataUnavailable }
            if box.kind == "moov" {
                guard box.size <= 4 * 1024 * 1024 else { throw DownloadSourceProbeError.metadataUnavailable }
                let movie: Data
                if box.size <= Int64(part.data.count - position) {
                    movie = part.data.subdata(in: position..<(position + Int(box.size)))
                } else { movie = try await read(source, offset: offset, length: Int(box.size), matching: first).data }
                return try Self.metadata(in: movie)
            }
            offset += box.size
        }
        throw DownloadSourceProbeError.metadataUnavailable
    }

    private func read(_ source: ResolvedMediaDownload, offset: Int64, length: Int, matching: Slice? = nil) async throws -> Slice {
        guard offset >= 0, length > 0, length <= 4 * 1024 * 1024,
              offset <= Int64.max - Int64(length) else { throw DownloadSourceProbeError.metadataUnavailable }
        var request = DownloadSourceHeaders.request(url: source.url, headers: source.headers, timeout: 15)
        request.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await session.bytes(for: request, delegate: DownloadSourceRedirectPolicy())
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw DownloadSourceProbeError.metadataUnavailable }
        guard http.statusCode == 200 || http.statusCode == 206 else { throw DownloadSourceProbeError.rejected(http.statusCode) }
        guard http.url?.scheme == "https", http.url?.user == nil, http.url?.password == nil else { throw DownloadSourceProbeError.invalidVideo }
        var total: Int64?
        let expectedRead: Int64
        if http.statusCode == 206 {
            guard let range = http.value(forHTTPHeaderField: "Content-Range"), range.hasPrefix("bytes "),
                  let slash = range.firstIndex(of: "/"), let dash = range.firstIndex(of: "-"), dash < slash,
                  let start = Int64(range[range.index(range.startIndex, offsetBy: 6)..<dash]), start == offset,
                  let end = Int64(range[range.index(after: dash)..<slash]), end >= start,
                  end - start < Int64(length), let fullSize = Int64(range[range.index(after: slash)...]),
                  fullSize > end else { throw DownloadSourceProbeError.metadataUnavailable }
            total = fullSize
            expectedRead = end - start + 1
        } else {
            // A small complete file is safe; never accidentally read a whole
            // multi-gigabyte response from a server ignoring Range.
            guard offset == 0, response.expectedContentLength >= 0,
                  response.expectedContentLength <= Int64(length) else { throw DownloadSourceProbeError.metadataUnavailable }
            total = response.expectedContentLength
            expectedRead = response.expectedContentLength
        }
        let etag = http.value(forHTTPHeaderField: "ETag")
        if let matching, matching.total != total || (matching.etag != nil && etag != matching.etag) {
            throw DownloadSourceProbeError.changedSource
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < length else { throw DownloadSourceProbeError.metadataUnavailable }
            data.append(byte)
        }
        if offset == 0 {
            do { try DownloadFiles.validateVideo(response: http, header: data) }
            catch { throw DownloadSourceProbeError.invalidVideo }
        }
        guard !data.isEmpty, Int64(data.count) == expectedRead else { throw DownloadSourceProbeError.metadataUnavailable }
        return Slice(data: data, offset: offset, total: total, etag: etag)
    }

    static func metadata(in data: Data) throws -> Metadata {
        var dimensions: [(Int, Int)] = []
        var codecs: [String] = []
        func visit(_ start: Int, _ end: Int, depth: Int) throws {
            guard depth < 10 else { throw DownloadSourceProbeError.metadataUnavailable }
            var cursor = start
            while cursor < end {
                guard let item = box(data, at: cursor), item.size <= Int64(end - cursor),
                      item.size >= Int64(item.header) else { throw DownloadSourceProbeError.metadataUnavailable }
                let stop = cursor + Int(item.size), inner = cursor + item.header
                if ["moov", "trak", "mdia", "minf", "stbl"].contains(item.kind) {
                    try visit(inner, stop, depth: depth + 1)
                } else if item.kind == "stsd" {
                    guard inner + 8 <= stop else { throw DownloadSourceProbeError.metadataUnavailable }
                    var entry = inner + 8
                    while entry < stop {
                        guard let sample = box(data, at: entry), sample.size <= Int64(stop - entry) else {
                            throw DownloadSourceProbeError.metadataUnavailable
                        }
                        if sample.kind == "encv" || sample.kind == "enca" { throw OfflineVideoError.protectedContent }
                        codecs.append(sample.kind)
                        if ["avc1", "avc3", "hvc1", "hev1", "av01", "vp09", "mp4v"].contains(sample.kind) {
                            guard sample.size >= 36 else { throw DownloadSourceProbeError.metadataUnavailable }
                            let width = Int(data[entry + 32]) * 256 + Int(data[entry + 33])
                            let height = Int(data[entry + 34]) * 256 + Int(data[entry + 35])
                            if width > 0 && height > 0 { dimensions.append((width, height)) }
                        }
                        entry += Int(sample.size)
                    }
                }
                cursor = stop
            }
        }
        try visit(0, data.count, depth: 0)
        guard let largest = dimensions.max(by: { $0.0 * $0.1 < $1.0 * $1.1 }) else {
            throw DownloadSourceProbeError.metadataUnavailable
        }
        return Metadata(width: largest.0, height: largest.1, codecs: codecs)
    }

    private static func box(_ data: Data, at offset: Int) -> Box? {
        guard offset >= 0, offset <= data.count - 8 else { return nil }
        let value = data[offset..<(offset + 4)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let kind = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
        let size: UInt64
        let header: Int
        if value == 1 {
            guard offset <= data.count - 16 else { return nil }
            size = data[(offset + 8)..<(offset + 16)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }; header = 16
        } else { size = value; header = 8 }
        guard size >= UInt64(header), size <= UInt64(Int64.max) else { return nil }
        return Box(offset: offset, size: Int64(size), kind: kind, header: header)
    }
}

private final class DownloadSourceRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(DownloadSourceHeaders.redirected(request, from: response.url))
    }
}
