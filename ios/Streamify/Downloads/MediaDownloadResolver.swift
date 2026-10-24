import Foundation

struct ResolvedMediaDownload {
    let url: URL
    let quality: Int
}

enum MediaDownloadResolutionError: LocalizedError {
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
            return "No download is available at this quality. Select a higher resolution and try again."
        case .unsafeSource:
            return "The source did not provide a supported HTTPS video file. Try streaming this title instead."
        case .incompatibleSource:
            return "The available download files cannot be played by this iPhone. Try streaming this title or choose another download source."
        }
    }
}

/// Resolves the same movie/TV file source used by the Android download flow.
/// Metadata requests are bounded; embedded players, playlists, and DRM are never downloaded.
struct MediaDownloadResolver {
    private let session: URLSession
    private let sourceValidator: @Sendable (URL) async throws -> Void

    init(session: URLSession = .shared,
         sourceValidator: @escaping @Sendable (URL) async throws -> Void = { try await OfflineVideoValidation.validateRemoteSource($0) }) {
        self.session = session
        self.sourceValidator = sourceValidator
    }

    func resolve(media: MediaItem, season: Int = 1, episode: Int = 1,
                 maximumQuality: Int = 1080) async throws -> ResolvedMediaDownload {
        try Task.checkCancellation()
        guard media.id > 0, media.kind == .movie || media.kind == .tv else {
            throw MediaDownloadResolutionError.unsupportedMedia
        }
        guard media.kind != .tv || (season > 0 && episode > 0) else {
            throw MediaDownloadResolutionError.invalidEpisode
        }
        let qualities = [1080, 720, 480, 360].filter { $0 <= maximumQuality }
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
        var checkedSources = Set<URL>()
        for quality in qualities {
            guard let item = available[String(quality)] as? [String: Any],
                  let value = item["url"] as? String, !value.isEmpty else { continue }
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
            do {
                try await sourceValidator(url)
                try Task.checkCancellation()
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                if let error = error as? OfflineVideoError, error.isCompatibilityIssue {
                    foundIncompatibleSource = true
                    continue
                }
                throw MediaDownloadResolutionError.unavailable
            }
            return ResolvedMediaDownload(url: url, quality: quality)
        }
        if foundIncompatibleSource { throw MediaDownloadResolutionError.incompatibleSource }
        if foundPlaylist { throw MediaDownloadResolutionError.streamingOnly }
        throw foundAddress ? MediaDownloadResolutionError.unsafeSource : MediaDownloadResolutionError.qualityUnavailable
    }

    private static let tokenCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/_=-")
    private static let pathComponentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

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
