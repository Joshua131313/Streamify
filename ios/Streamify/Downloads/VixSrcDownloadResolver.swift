import AVFoundation
import Foundation

enum VixSrcDownloadError: LocalizedError, Equatable {
    case invalidResponse, unsafeSource, expiredSource, unsupportedProtection, notVOD, englishAudioUnavailable, nativeCapabilityUnavailable
    case http(status: Int, retryAfter: String?)
    case redirectRefused(status: Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The download source returned incomplete metadata."
        case .unsafeSource: return "The download source returned an unsupported address."
        case .expiredSource: return "The download source expired. Request a fresh download."
        case .unsupportedProtection: return "This source uses unsupported protected playback."
        case .notVOD: return "This source does not provide a complete on-demand download."
        case .englishAudioUnavailable: return "The source does not provide playable English audio."
        case .nativeCapabilityUnavailable: return "This iPhone could not verify the exact selected download quality."
        case .redirectRefused: return "The download source redirected its metadata request."
        case .http(let status, _): return "The download source could not complete the request (HTTP \(status))."
        }
    }
}

/// Exact, advertised manifest selection supplied to Apple's public capability
/// check. This is not a playlist rewrite or a license/key retrieval interface.
struct VixSrcDownloadSelection: Sendable {
    let masterURL: URL
    let videoURL: URL
    let englishAudioURL: URL
    let width: Int
    let height: Int
    let codecs: [String]
    let expiresAt: Date
}

struct VixSrcNativeCapability: Sendable {
    let variantURL: URL
    let width: Int
    let height: Int
    let audioLanguage: String
    let englishAudioPlayable: Bool
}

/// Five fresh, bounded metadata requests
/// follow the provider's public API and its own published player construction.
/// Apple owns normal AES-128 HLS handling; this adapter never fetches key bytes,
/// segments or licenses, rewrites playlists, or enables a proxy/custom loader.
struct VixSrcDownloadResolver {
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let nativeCapability: (@Sendable (VixSrcDownloadSelection) async throws -> VixSrcNativeCapability)?
    private static let origin = URL(string: "https://vixsrc.to")!
    private static let requestSeconds: UInt64 = 10

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() },
         nativeCapability: (@Sendable (VixSrcDownloadSelection) async throws -> VixSrcNativeCapability)? = nil) {
        self.session = session; self.now = now; self.nativeCapability = nativeCapability
    }

    func resolve(media: MediaItem, season: Int = 1, episode: Int = 1, quality: Int = 1080,
                 excludingSources: Set<String> = []) async throws -> ResolvedMediaDownload {
        try Task.checkCancellation()
        guard media.id > 0, media.kind == .movie || media.kind == .tv else { throw MediaDownloadResolutionError.unsupportedMedia }
        guard media.kind != .tv || (season > 0 && episode > 0) else { throw MediaDownloadResolutionError.invalidEpisode }
        guard [1080, 720].contains(quality) else { throw MediaDownloadResolutionError.qualityUnavailable }
        let identityPath = media.kind == .movie ? "/movie/\(media.id)" : "/tv/\(media.id)/\(season)/\(episode)"
        let page = Self.origin.appendingPathComponent(String(identityPath.dropFirst()))
        let api = Self.origin.appendingPathComponent("api" + identityPath)
        let object = try JSONSerialization.jsonObject(with: await document(api, referer: page, limit: 32 * 1024))
        guard let fields = object as? [String: Any], let src = fields["src"] as? String,
              let embed = URL(string: src, relativeTo: Self.origin)?.absoluteURL else { throw VixSrcDownloadError.invalidResponse }
        try Self.sameOrigin(embed)
        let embedID = try Self.resourceID(embed, prefix: "/embed/")
        let embedQuery = try Self.query(embed)
        guard Self.english(embedQuery["lang"] ?? "en") else { throw VixSrcDownloadError.englishAudioUnavailable }
        _ = try Self.expiry(embedQuery["expires"], after: now())
        let fullHDAllowed = ["1", "true"].contains((embedQuery["canPlayFHD"] ?? "").lowercased())
        guard quality != 1080 || fullHDAllowed else { throw MediaDownloadResolutionError.qualityUnavailable }
        // Do not cache the API result: its advertised embed currently expires
        // in approximately ten seconds and must be consumed immediately.
        let html = try Self.text(await document(embed, referer: page, limit: 256 * 1024))
        guard !Self.challenge(html) else { throw VixSrcDownloadError.invalidResponse }
        let published = Self.matches(#"window\.masterPlaylist\s*=\s*\{\s*params:\s*\{([\s\S]*?)\}\s*,\s*url:\s*['"]([^'"]+)['"]\s*,?\s*\}"#, html)
        guard published.count == 1, published[0].count == 2,
              let raw = URL(string: published[0][1].replacingOccurrences(of: "\\/", with: "/")),
              var canonical = URLComponents(url: raw, resolvingAgainstBaseURL: false) else { throw VixSrcDownloadError.invalidResponse }
        try Self.sameOrigin(raw)
        guard try Self.resourceID(raw, prefix: "/playlist/") == embedID else { throw VixSrcDownloadError.invalidResponse }
        var query = try Self.query(raw)
        var orderedQuery = canonical.queryItems ?? []
        let pairs = Self.matches(#"['"]([A-Za-z0-9_-]+)['"]\s*:\s*['"]([^'"\\]*)['"]"#, published[0][0])
        guard !pairs.isEmpty, pairs.count <= 12 else { throw VixSrcDownloadError.invalidResponse }
        for pair in pairs where !pair[1].isEmpty {
            guard query[pair[0]] == nil, pair[1].utf8.count <= 4096 else { throw VixSrcDownloadError.invalidResponse }
            query[pair[0]] = pair[1]
            orderedQuery.append(URLQueryItem(name: pair[0], value: pair[1]))
        }
        if let cdn = embedQuery["cdn"] {
            guard query["cdn"] == nil else { throw VixSrcDownloadError.invalidResponse }
            query["cdn"] = cdn; orderedQuery.append(URLQueryItem(name: "cdn", value: cdn))
        }
        guard query["h"] == nil, query["lang"] == nil else { throw VixSrcDownloadError.invalidResponse }
        if fullHDAllowed {
            query["h"] = "1"
            orderedQuery.append(URLQueryItem(name: "h", value: "1"))
        }
        query["lang"] = embedQuery["lang"] ?? "en"
        orderedQuery.append(URLQueryItem(name: "lang", value: embedQuery["lang"] ?? "en"))
        canonical.queryItems = orderedQuery
        guard let master = canonical.url else { throw VixSrcDownloadError.invalidResponse }
        let expiry = try Self.expiry(query["expires"], after: now())
        guard !excludingSources.contains(master.absoluteString) else { throw MediaDownloadResolutionError.incompatibleSource }
        let playlist = try Self.playlist(await document(master, referer: embed, limit: 256 * 1024), base: master)
        let selection = try Self.selection(playlist, master: master, quality: quality, expiry: expiry)
        for url in [selection.videoURL, selection.englishAudioURL] {
            try Self.sameOrigin(url)
            let rendition = try Self.playlist(await document(url, referer: embed, limit: 512 * 1024), base: url)
            try Self.requireVOD(rendition)
        }
        try Task.checkCancellation()
        let evidence: VixSrcNativeCapability
        if let nativeCapability { evidence = try await nativeCapability(selection) }
        else { evidence = try await Self.nativeEvidence(selection) }
        try Task.checkCancellation()
        guard evidence.variantURL == selection.videoURL,
              evidence.width == selection.width, evidence.height == selection.height else {
            throw VixSrcDownloadError.nativeCapabilityUnavailable
        }
        guard evidence.englishAudioPlayable, Self.english(evidence.audioLanguage) else { throw VixSrcDownloadError.englishAudioUnavailable }
        try OfflineVideoValidation.requireQuality(quality, width: evidence.width, height: evidence.height)
        guard expiry > now() else { throw VixSrcDownloadError.expiredSource }
        var resolved = ResolvedMediaDownload(url: master, quality: quality, expiresAt: expiry,
            codec: selection.codecs.first, sourceID: "VixSrc", actualWidth: evidence.width,
            actualHeight: evidence.height, actualCodecs: selection.codecs, transport: .hlsVOD, audioLanguage: "en")
        resolved.hlsSource = HLSDownloadSource(masterURL: master, quality: quality, audioLanguage: "en",
            protection: .clearOrIdentityAES128, isVOD: true)
        return resolved
    }

    private func document(_ url: URL, referer: URL, limit: Int) async throws -> Data {
        try Self.sameOrigin(url); try Self.sameOrigin(referer)
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await fetch(url, referer: referer, limit: limit) }
            group.addTask { try await Task.sleep(nanoseconds: Self.requestSeconds * 1_000_000_000); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw VixSrcDownloadError.invalidResponse }
            return value
        }
    }

    private func fetch(_ url: URL, referer: URL, limit: Int) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Double(Self.requestSeconds))
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let policy = VixSrcMetadataRedirectPolicy()
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: policy)
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            if let refusal = policy.refusal { throw refusal }
            guard let http = response as? HTTPURLResponse, http.url == url else { throw VixSrcDownloadError.invalidResponse }
            try Self.sameOrigin(http.url!)
            guard http.statusCode == 200 else {
                throw VixSrcDownloadError.http(status: http.statusCode,
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After").map { String($0.prefix(128)) })
            }
            guard response.expectedContentLength <= Int64(limit) else { throw VixSrcDownloadError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw VixSrcDownloadError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let refusal = policy.refusal { throw refusal }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
    }

    private static func selection(_ lines: [String], master: URL, quality: Int, expiry: Date) throws -> VixSrcDownloadSelection {
        var audio: [(String, URL)] = [], variants: [(Int, Int, [String], String, URL)] = []
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#EXT-X-MEDIA:") {
                let fields = try attributes(line)
                if fields["TYPE"] == "AUDIO", let group = fields["GROUP-ID"],
                   english(fields["LANGUAGE"] ?? ""), let uri = fields["URI"] {
                    audio.append((group, try advertised(uri, base: master)))
                }
            }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let fields = try attributes(line)
                let dimensions = (fields["RESOLUTION"] ?? "").split(separator: "x")
                guard dimensions.count == 2, let width = Int(dimensions[0]), let height = Int(dimensions[1]),
                      width > 0, width <= 65_535, height > 0, height <= 65_535,
                      let group = fields["AUDIO"], let codecs = fields["CODECS"],
                      index + 1 < lines.count, !lines[index + 1].isEmpty, !lines[index + 1].hasPrefix("#") else {
                    throw VixSrcDownloadError.invalidResponse
                }
                let codes = codecs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard !codes.isEmpty, codes.count <= 8, codes.allSatisfy({ $0.utf8.count <= 128 }) else { throw VixSrcDownloadError.invalidResponse }
                variants.append((width, height, codes, group, try advertised(lines[index + 1], base: master)))
            }
        }
        guard variants.count <= 50, audio.count <= 50 else { throw VixSrcDownloadError.invalidResponse }
        let exact = variants.filter { (try? OfflineVideoValidation.requireQuality(quality, width: $0.0, height: $0.1)) != nil }
        guard !exact.isEmpty else { throw MediaDownloadResolutionError.qualityUnavailable }
        guard let chosen = exact.first, let english = audio.first(where: { $0.0 == chosen.3 }) else { throw VixSrcDownloadError.englishAudioUnavailable }
        return VixSrcDownloadSelection(masterURL: master, videoURL: chosen.4, englishAudioURL: english.1,
            width: chosen.0, height: chosen.1, codecs: chosen.2, expiresAt: expiry)
    }

    private static func playlist(_ data: Data, base: URL) throws -> [String] {
        let text = try text(data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("#EXTM3U\n") || text.hasPrefix("#EXTM3U\r\n") else { throw VixSrcDownloadError.invalidResponse }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count <= 20_000, !lines.contains(where: { $0.utf8.count > 8192 }) else { throw VixSrcDownloadError.invalidResponse }
        for line in lines where !line.isEmpty {
            // The observed provider uses literal ordinary VOD URIs. Reject
            // additional indirection instead of letting native metadata load
            // an unreviewed content-steering/variable/sidecar service.
            guard !line.contains("{$"), !line.hasPrefix("#EXT-X-CONTENT-STEERING:"),
                  !line.hasPrefix("#EXT-X-DEFINE:"), !line.hasPrefix("#EXT-X-SESSION-DATA:") else {
                throw VixSrcDownloadError.invalidResponse
            }
            if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                let key = try attributes(line)
                guard let method = key["METHOD"], ["NONE", "AES-128"].contains(method),
                      key["KEYFORMAT"] == nil || key["KEYFORMAT"] == "identity",
                      key["KEYFORMATVERSIONS"] == nil || key["KEYFORMATVERSIONS"] == "1" else { throw VixSrcDownloadError.unsupportedProtection }
                if method == "AES-128" {
                    guard let uri = key["URI"] else { throw VixSrcDownloadError.unsupportedProtection }
                    _ = try advertised(uri, base: base)
                } else if key["URI"] != nil { throw VixSrcDownloadError.unsupportedProtection }
            }
            if line.hasPrefix("#") {
                for uri in matches(#"(?:^|,)URI="([^"]+)""#, String(line.split(separator: ":", maxSplits: 1).last ?? "")) {
                    _ = try advertised(uri[0], base: base)
                }
            } else { _ = try advertised(line, base: base) }
        }
        return lines
    }

    private static func requireVOD(_ lines: [String]) throws {
        guard lines.contains("#EXT-X-ENDLIST"), lines.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
              !lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }) else { throw VixSrcDownloadError.notVOD }
        let entries = lines.filter { $0.hasPrefix("#EXTINF:") }
        let durations = entries.compactMap { Double($0.dropFirst(8).split(separator: ",").first ?? "") }
        let segments = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !durations.isEmpty, durations.count == entries.count, segments.count == durations.count,
              durations.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 3600 }),
              durations.reduce(0, +) <= 24 * 3600,
              !segments.isEmpty else { throw VixSrcDownloadError.notVOD }
    }

    private static func attributes(_ line: String) throws -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { throw VixSrcDownloadError.invalidResponse }
        let input = String(line[line.index(after: colon)...]) as NSString
        let regex = try NSRegularExpression(pattern: #"([A-Z0-9-]+)=("[^"]*"|[^,]*)(?:,|$)"#)
        let parsed = regex.matches(in: input as String, range: NSRange(location: 0, length: input.length))
        var output: [String: String] = [:], consumed = 0
        for match in parsed {
            guard match.range.location == consumed else { throw VixSrcDownloadError.invalidResponse }
            let key = input.substring(with: match.range(at: 1)); var value = input.substring(with: match.range(at: 2))
            if value.hasPrefix("\"") { value.removeFirst(); value.removeLast() }
            guard output[key] == nil else { throw VixSrcDownloadError.invalidResponse }
            output[key] = value; consumed = match.range.location + match.range.length
        }
        guard consumed == input.length, !output.isEmpty else { throw VixSrcDownloadError.invalidResponse }
        return output
    }

    private static func query(_ url: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            guard !item.name.isEmpty, item.name.utf8.count <= 128, result[item.name] == nil,
                  let value = item.value, value.utf8.count <= 4096 else { throw VixSrcDownloadError.invalidResponse }
            result[item.name] = value
        }
        return result
    }
    private static func resourceID(_ url: URL, prefix: String) throws -> String {
        let id = String(url.path.dropFirst(prefix.count))
        guard url.path.hasPrefix(prefix), !id.isEmpty, id.utf8.count <= 24,
              id.utf8.allSatisfy({ (48...57).contains($0) }) else { throw VixSrcDownloadError.invalidResponse }
        return id
    }
    private static func expiry(_ value: String?, after now: Date) throws -> Date {
        guard let value, value.utf8.count <= 12, !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let seconds = TimeInterval(value), seconds.isFinite else { throw VixSrcDownloadError.invalidResponse }
        let date = Date(timeIntervalSince1970: seconds)
        guard date > now else { throw VixSrcDownloadError.expiredSource }
        return date
    }
    private static func sameOrigin(_ url: URL) throws {
        try safe(url)
        guard url.host?.lowercased() == origin.host else { throw VixSrcDownloadError.unsafeSource }
    }
    private static func safe(_ url: URL) throws {
        guard url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443, url.absoluteString.utf8.count <= 16_384,
              host.lowercased() != "surge.flooderrr.store", !url.path.lowercased().contains("/proxy") else { throw VixSrcDownloadError.unsafeSource }
    }
    private static func advertised(_ value: String, base: URL) throws -> URL {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL else { throw VixSrcDownloadError.unsafeSource }
        try safe(url); return url
    }
    private static func text(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8), !value.contains("\0") else { throw VixSrcDownloadError.invalidResponse }
        return value
    }
    private static func english(_ value: String) -> Bool { ["en", "eng"].contains(value.lowercased()) || value.lowercased().hasPrefix("en-") }
    private static func challenge(_ value: String) -> Bool { ["cf-chl-", "challenge-platform", "captcha", "turnstile"].contains { value.lowercased().contains($0) } }
    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (1..<match.numberOfRanges).map { source.substring(with: match.range(at: $0)) }
        }
    }

    private static func nativeEvidence(_ selected: VixSrcDownloadSelection) async throws -> VixSrcNativeCapability {
        let asset = AVURLAsset(url: selected.masterURL)
        defer { asset.cancelLoading() }
        return try await withThrowingTaskGroup(of: VixSrcNativeCapability.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    let playable = try await asset.load(.isPlayable)
                    #if DEBUG
                    let protected = try? await asset.load(.hasProtectedContent)
                    print("VIXSRC_NATIVE_CAPABILITY_METADATA playable=\(playable) protected=\(String(describing: protected))")
                    #endif
                    // The selected manifests already exclude FairPlay,
                    // SAMPLE-AES and nonidentity key formats. Apple's generic
                    // flag can also be true for ordinary identity AES-128.
                    guard playable else { throw VixSrcDownloadError.nativeCapabilityUnavailable }
                    let variants = try await asset.load(.variants)
                    let matching = variants.filter { variant in
                        guard let size = variant.videoAttributes?.presentationSize else { return false }
                        return size.width == CGFloat(selected.width) && size.height == CGFloat(selected.height)
                    }
                    #if DEBUG
                    let sizes = variants.compactMap { $0.videoAttributes?.presentationSize }.map { "\($0.width)x\($0.height)" }.joined(separator: ",")
                    print("VIXSRC_NATIVE_CAPABILITY_VARIANTS count=\(variants.count) matchingDimensions=\(matching.count) sizes=\(sizes)")
                    #endif
                    let matchedURL: URL
                    if #available(iOS 26.0, *) {
                        #if DEBUG
                        print("VIXSRC_NATIVE_CAPABILITY_URL_MATCH exact=\(matching.contains(where: { $0.url == selected.videoURL }))")
                        #endif
                        guard let variant = matching.first(where: { $0.url == selected.videoURL }) else {
                            throw VixSrcDownloadError.nativeCapabilityUnavailable
                        }
                        matchedURL = variant.url
                    } else {
                        // Earlier native APIs expose dimensions but no URL.
                        // A unique matching variant maps to the exact advertised
                        // rendition; ambiguous same-size variants are rejected.
                        guard matching.count == 1 else { throw VixSrcDownloadError.nativeCapabilityUnavailable }
                        matchedURL = selected.videoURL
                    }
                    guard let audible = try await asset.loadMediaSelectionGroup(for: .audible),
                          let english = audible.options.first(where: { Self.english($0.extendedLanguageTag ?? "") && $0.isPlayable }) else { throw VixSrcDownloadError.englishAudioUnavailable }
                    try Task.checkCancellation()
                    return VixSrcNativeCapability(variantURL: matchedURL, width: selected.width, height: selected.height,
                        audioLanguage: english.extendedLanguageTag ?? "", englishAudioPlayable: english.isPlayable)
                } onCancel: { asset.cancelLoading() }
            }
            group.addTask { try await Task.sleep(nanoseconds: 12_000_000_000); throw VixSrcDownloadError.nativeCapabilityUnavailable }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw VixSrcDownloadError.nativeCapabilityUnavailable }
            return value
        }
    }
}

private final class VixSrcMetadataRedirectPolicy: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var status: Int?
    var refusal: VixSrcDownloadError? { lock.lock(); defer { lock.unlock() }; return status.map { .redirectRefused(status: $0) } }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); status = response.statusCode; lock.unlock()
        completionHandler(nil)
    }
}
