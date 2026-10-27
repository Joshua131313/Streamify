import Foundation

enum DaraTechDownloadError: LocalizedError, Equatable {
    case missingAPIKey, invalidAPIKey, identityUnavailable, ambiguousIdentity, invalidResponse
    case http(status: Int, retryAfter: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your own DaraTech API key to use this optional download source."
        case .invalidAPIKey: return "The DaraTech API key could not be used."
        case .identityUnavailable: return "This download source could not verify the exact title, year and media type."
        case .ambiguousIdentity: return "This download source returned more than one matching title."
        case .invalidResponse: return "The download source returned unreadable or incomplete metadata."
        case .http(let status, _):
            return status == 429 ? "The download API rate limit was reached. Please wait before trying again."
                : "The download API could not complete this request (HTTP \(status))."
        }
    }
}

/// An opt-in adapter, deliberately disconnected from app settings and download
/// routing. Its caller must supply their own key; no default or demo credential
/// exists here. Only metadata requests receive it, and redirects are refused.
struct DaraTechDownloadResolver {
    private let session: URLSession
    private let inspectSource: (@Sendable (ResolvedMediaDownload) async throws -> DownloadSourceProbe.Metadata)?
    private let validateNativeSource: (@Sendable (URL) async throws -> Void)?
    private static let host = "apimovie.runflix.name.ng"
    private static let maximumMetadataBytes = 512 * 1024
    private static let maximumFileBytes: Int64 = 64 * 1024 * 1024 * 1024

    init(session: URLSession = .shared,
         inspectSource: (@Sendable (ResolvedMediaDownload) async throws -> DownloadSourceProbe.Metadata)? = nil,
         validateNativeSource: (@Sendable (URL) async throws -> Void)? = nil) {
        self.session = session
        self.inspectSource = inspectSource
        self.validateNativeSource = validateNativeSource
    }

    func resolve(media: MediaItem, apiKey: String, season: Int = 1, episode: Int = 1,
                 quality: Int = 1080, excludingSources: Set<String> = []) async throws -> ResolvedMediaDownload {
        try Task.checkCancellation()
        guard media.id > 0, media.kind == .movie || media.kind == .tv else {
            throw MediaDownloadResolutionError.unsupportedMedia
        }
        guard media.kind != .tv || (season > 0 && episode > 0) else {
            throw MediaDownloadResolutionError.invalidEpisode
        }
        guard [1080, 720, 480, 360].contains(quality) else { throw MediaDownloadResolutionError.qualityUnavailable }
        guard let year = Int(media.year), media.year.count == 4, (1800...3000).contains(year),
              !Self.normalized(media.title).isEmpty, media.title.utf8.count <= 512 else {
            throw DaraTechDownloadError.identityUnavailable
        }
        guard !apiKey.isEmpty else { throw DaraTechDownloadError.missingAPIKey }
        guard apiKey.utf8.count <= 4096,
              !apiKey.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw DaraTechDownloadError.invalidAPIKey
        }

        let searchURL = Self.metadataURL(path: "/v1/search", query: [URLQueryItem(name: "q", value: media.title)])
        let search = try await object(at: searchURL, apiKey: apiKey)
        guard let items = search["items"] as? [[String: Any]], items.count <= 100 else {
            throw DaraTechDownloadError.invalidResponse
        }
        var matches = Set<String>()
        for item in items where Self.matches(item, media: media, year: year) {
            if let subject = Self.subjectID(item) { matches.insert(subject) }
        }
        guard !matches.isEmpty else { throw DaraTechDownloadError.identityUnavailable }
        guard matches.count == 1, let subject = matches.first else { throw DaraTechDownloadError.ambiguousIdentity }
        try Task.checkCancellation()

        // Request the actual selected episode. Never rely on the API's default
        // season or episode, or reuse a source returned for a different tier.
        let path = media.kind == .movie ? "/v1/movies/\(subject)/download"
            : "/v1/tvshows/\(subject)/season/\(season)/episode/\(episode)/download"
        let downloads = try await object(at: Self.metadataURL(path: path), apiKey: apiKey)
        guard !Self.hasDRM(downloads), let links = downloads["links"] as? [[String: Any]], links.count <= 100 else {
            throw DaraTechDownloadError.invalidResponse
        }
        if Self.hasIdentity(downloads), !Self.matches(downloads, media: media, year: year) {
            throw DaraTechDownloadError.identityUnavailable
        }
        let exact = links.filter { Self.integer($0["resolution"]) == quality }
        guard !exact.isEmpty else { throw MediaDownloadResolutionError.qualityUnavailable }
        var checked = Set<URL>()
        var lastError: Error?
        var excluded = false
        for link in exact.prefix(4) {
            try Task.checkCancellation()
            guard let address = link["url"] as? String,
                  let url = Self.videoURL(address), !address.contains(apiKey),
                  Self.validLink(link, url: url, subject: subject, kind: media.kind,
                                 season: season, episode: episode, quality: quality) else {
                lastError = MediaDownloadResolutionError.unsafeSource
                continue
            }
            guard checked.insert(url).inserted else { continue }
            if excludingSources.contains(address) { excluded = true; continue }
            var headers = DownloadSourceHeaders.sanitized(link["headers"] as? [String: String] ?? [:])
            // Even optional non-secret source context must not reflect the
            // caller's metadata credential into a media request or persistence.
            headers = headers.filter { !$0.value.contains(apiKey) }
            var candidate = ResolvedMediaDownload(url: url, quality: quality, headers: headers,
                                                 sourceID: "DaraTech")
            do {
                let metadata: DownloadSourceProbe.Metadata
                if let inspectSource { metadata = try await inspectSource(candidate) }
                else { metadata = try await DownloadSourceProbe(session: session).inspect(candidate) }
                try OfflineVideoValidation.requireQuality(quality, width: metadata.width, height: metadata.height)
                candidate.actualWidth = metadata.width
                candidate.actualHeight = metadata.height
                candidate.actualCodecs = metadata.codecs
                candidate.codec = metadata.codecs.first
                // Header-dependent media is checked with URLSession here and
                // by the existing real local AVFoundation validator after the
                // transfer. A bare-URL transport error is not a codec verdict.
                if headers.isEmpty {
                    if let validateNativeSource { try await validateNativeSource(url) }
                    else { try await OfflineVideoValidation.validateRemoteSource(url) }
                }
                try Task.checkCancellation()
                return candidate
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                if let failure = error as? DownloadSourceProbeError {
                    if failure.stopsFallback { throw failure }
                    lastError = failure
                } else if let failure = error as? OfflineVideoError,
                          failure.isCompatibilityIssue || failure == .qualityMismatch {
                    lastError = failure
                } else {
                    // Preserve native unavailability and transport errors;
                    // neither authorizes another request or a quality change.
                    throw error
                }
            }
        }
        if let lastError { throw lastError }
        if excluded { throw MediaDownloadResolutionError.incompatibleSource }
        throw MediaDownloadResolutionError.unavailable
    }

    private func object(at url: URL, apiKey: String) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard Self.isMetadataOrigin(url) else { throw DaraTechDownloadError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: DaraTechMetadataRedirectPolicy())
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.url == url,
                  Self.isMetadataOrigin(http.url) else { throw DaraTechDownloadError.invalidResponse }
            guard http.statusCode == 200 else {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").map { String($0.prefix(128)) }
                throw DaraTechDownloadError.http(status: http.statusCode, retryAfter: retryAfter)
            }
            guard response.expectedContentLength <= Int64(Self.maximumMetadataBytes) else {
                throw DaraTechDownloadError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumMetadataBytes else { throw DaraTechDownloadError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["success"] as? Bool == true,
                  result["status"] == nil || Self.integer(result["status"]) == 200 else {
                throw DaraTechDownloadError.invalidResponse
            }
            return result
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private static func metadataURL(path: String, query: [URLQueryItem] = []) -> URL {
        var address = URLComponents()
        address.scheme = "https"; address.host = host; address.path = path
        if !query.isEmpty { address.queryItems = query }
        // All path components are fixed literals or validated ASCII digits.
        return address.url!
    }

    private static func isMetadataOrigin(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == host && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil && url.fragment == nil
    }

    private static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func matches(_ item: [String: Any], media: MediaItem, year: Int) -> Bool {
        guard let title = item["title"] as? String, normalized(title) == normalized(media.title),
              integer(item["subjectType"]) == (media.kind == .tv ? 1 : 2) else { return false }
        let explicitYear = integer(item["year"])
        let releaseYear = (item["releaseDate"] as? String).flatMap { Int($0.prefix(4)) }
        guard (explicitYear ?? releaseYear) == year,
              explicitYear == nil || explicitYear == year,
              releaseYear == nil || releaseYear == year else { return false }
        if let category = item["category"] as? String {
            guard normalized(category) == (media.kind == .tv ? "tv show" : "movie") else { return false }
        }
        let external = item["externalIds"] as? [String: Any] ?? item["external_ids"] as? [String: Any] ?? [:]
        for value in [item["tmdb"], item["tmdbId"], item["tmdb_id"], external["tmdb"], external["tmdb_id"]] {
            if let value, !(value is NSNull), integer(value) != media.id { return false }
        }
        return true
    }

    private static func hasIdentity(_ item: [String: Any]) -> Bool {
        ["title", "subjectType", "year", "releaseDate", "tmdb", "tmdbId", "tmdb_id", "externalIds", "external_ids"]
            .contains { item[$0] != nil }
    }

    private static func subjectID(_ item: [String: Any]) -> String? {
        let id = item["id"] as? String, subject = item["subjectId"] as? String
        guard let value = subject ?? id, !value.isEmpty, value.utf8.count <= 32,
              value.utf8.allSatisfy({ (48...57).contains($0) }), value.contains(where: { $0 != "0" }),
              id == nil || id == value, subject == nil || subject == value else { return nil }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        if let string = value as? String, !string.isEmpty, string.utf8.allSatisfy({ (48...57).contains($0) }) { return Int(string) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue < Double(Int.max) else { return nil }
        return number.intValue
    }

    private static func videoURL(_ value: String) -> URL? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let parts = URLComponents(string: value), parts.scheme == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443, let url = parts.url,
              ["", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()),
              !(parts.queryItems ?? []).contains(where: { ["apikey", "api_key", "authorization", "cookie"].contains($0.name.lowercased()) }) else { return nil }
        return url
    }

    private static func validLink(_ item: [String: Any], url: URL, subject: String, kind: MediaKind,
                                  season: Int, episode: Int, quality: Int) -> Bool {
        guard (item["format"] as? String)?.lowercased() == "mp4", !hasDRM(item),
              integer(item["requireMemberType"]) == 0,
              let size = integer(item["sizeBytes"] ?? item["size"]), size > 0, Int64(size) <= maximumFileBytes,
              item["size"] == nil || integer(item["size"]) == size,
              item["sizeBytes"] == nil || integer(item["sizeBytes"]) == size else { return false }
        if let label = item["quality"] as? String,
           let prefix = Int(label.prefix(while: { $0.isNumber })), prefix != quality { return false }
        if url.host == host {
            guard url.path == "/v1/media/download/\(subject)/\(quality)",
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
            let seasons = (parts.queryItems ?? []).filter { $0.name == "se" }
            let episodes = (parts.queryItems ?? []).filter { $0.name == "ep" }
            guard seasons.count == 1, episodes.count == 1,
                  seasons.first?.value == String(kind == .tv ? season : 0),
                  episodes.first?.value == String(kind == .tv ? episode : 0) else { return false }
        }
        return true
    }

    private static func hasDRM(_ item: [String: Any]) -> Bool {
        for key in ["drm", "drmInfo", "license", "licenseUrl", "licenseURL"] {
            guard let value = item[key], !(value is NSNull) else { continue }
            if let bool = value as? Bool { if bool { return true }; continue }
            if let string = value as? String { if !string.isEmpty && string.lowercased() != "false" { return true }; continue }
            return true
        }
        return false
    }
}

private final class DaraTechMetadataRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A metadata redirect is an error, including to another same-origin
        // path; this key is never forwarded to another URL or a media task.
        completionHandler(nil)
    }
}
