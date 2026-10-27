import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import XCTest

/// Manual, live-provider feasibility test. This directory is intentionally
/// outside StreamifyTests; normal application CI never runs these requests.
/// Apple handles ordinary AES-128 HLS keys. No key bytes, custom resource
/// loader, relay, private HTTP-header option, or playlist rewrite is used.
final class VixSrcNativeHLSDiagnosticsTests: XCTestCase {
    private static let origin = URL(string: "https://vixsrc.to")!
    private static let page = URL(string: "https://vixsrc.to/tv/124364/1/1")!
    private static let maximumObservedMediaBytes: Int64 = 32 * 1024 * 1024

    @MainActor
    func testNormalNativeMasterPlaybackAndBoundedDownloadAcceptance() async {
        var report: [String: Any] = ["observedAt": ISO8601DateFormatter().string(from: Date()),
            "tmdbID": 124364, "season": 1, "episode": 1,
            "nativeCustomHeaders": false, "nativeCustomResourceLoader": false,
            "manualKeyFetch": false, "completeOfflinePersistenceProven": false,
            "maximumObservedMediaBytes": Self.maximumObservedMediaBytes]
        var phase = "public metadata"
        do {
            let source = try await Self.freshSource()
            report["metadata"] = source.summary
            phase = "native master metadata"
            // A real native client uses its normal CoreMedia user agent. No
            // retry with changed identity or private header dictionary follows
            // a denial. This may differ from a bare Python metadata request.
            let asset = AVURLAsset(url: source.master)
            let watchdog = Task {
                do { try await Task.sleep(nanoseconds: 20_000_000_000); asset.cancelLoading() }
                catch { }
            }
            defer { watchdog.cancel(); asset.cancelLoading() }
            let variants = try await asset.load(.variants)
            guard let fullHD = variants.first(where: {
                guard let size = $0.videoAttributes?.presentationSize else { return false }
                return abs(size.width - 1920) <= 2 && abs(size.height - 1080) <= 2
            }) else { throw DiagnosticError.message("Native HLS metadata did not expose the advertised 1080p variant") }
            report["native1080VariantFound"] = true
            report["nativeVariantCount"] = variants.count
            let audioGroup = try await asset.loadMediaSelectionGroup(for: .audible)
            let preferred = try await asset.load(.preferredMediaSelection)
            guard let selection = preferred.mutableCopy() as? AVMutableMediaSelection,
                  let audioGroup,
                  let english = audioGroup.options.first(where: {
                      $0.extendedLanguageTag?.lowercased().hasPrefix("en") == true
                          || $0.displayName.lowercased().contains("english")
                  }) else { throw DiagnosticError.message("Native master did not offer an English audio selection") }
            selection.select(english, in: audioGroup)
            report["englishAudioOption"] = english.displayName
            report["englishAudioLanguage"] = english.extendedLanguageTag ?? "unknown"

            phase = "native master playback"
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 1
            item.preferredPeakBitRate = max(1, fullHD.peakBitRate ?? 0)
            item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
            item.select(english, in: audioGroup)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
                [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(output)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.allowsExternalPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false
            defer { player.pause(); player.replaceCurrentItem(with: nil) }
            var pixelWidth = 0, pixelHeight = 0
            var playbackSeconds = 0.0
            var transferred: Int64 = 0
            let deadline = Date().addingTimeInterval(8)
            player.playImmediately(atRate: 1)
            while Date() < deadline {
                try Task.checkCancellation()
                if item.status == .failed { throw item.error ?? DiagnosticError.message("AVPlayerItem failed") }
                let time = item.currentTime()
                if time.seconds.isFinite { playbackSeconds = time.seconds }
                if output.hasNewPixelBuffer(forItemTime: time),
                   let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                    pixelWidth = CVPixelBufferGetWidth(frame); pixelHeight = CVPixelBufferGetHeight(frame)
                }
                transferred = item.accessLog()?.events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) } ?? 0
                if transferred >= Self.maximumObservedMediaBytes { throw DiagnosticError.message("Native playback byte budget reached") }
                if pixelWidth == 1920 && pixelHeight == 1080 && playbackSeconds >= 1 { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            player.pause()
            report["pixelWidth"] = pixelWidth; report["pixelHeight"] = pixelHeight
            report["actualVideoFrame"] = pixelWidth > 0 && pixelHeight > 0
            report["actualPreview1080"] = pixelWidth == 1920 && pixelHeight == 1080
            report["playbackSeconds"] = playbackSeconds
            report["playbackObservedBytes"] = transferred
            let selectedAudioLanguage = item.currentMediaSelection.selectedMediaOption(in: audioGroup)?.extendedLanguageTag ?? "unknown"
            report["selectedEnglishAudio"] = selectedAudioLanguage
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            report["nativeAudioTrackCount"] = audioTracks.count
            var audioDecodable = false
            var audioCodecs: [String] = []
            for track in audioTracks {
                if (try? await track.load(.isDecodable)) == true { audioDecodable = true }
                for format in (try? await track.load(.formatDescriptions)) ?? [] {
                    audioCodecs.append(Self.fourCC(CMFormatDescriptionGetMediaSubType(format)))
                }
            }
            report["nativeAudioDecodable"] = audioDecodable
            report["nativeAudioCodecs"] = audioCodecs
            guard pixelWidth == 1920, pixelHeight == 1080, playbackSeconds >= 1,
                  selectedAudioLanguage.lowercased().hasPrefix("en"), !audioTracks.isEmpty, audioDecodable else {
                throw DiagnosticError.message("Native player did not demonstrate real 1080p video with selected English audio and a decodable audio track within the bounded preview")
            }

            phase = "bounded native download acceptance"
            report["probeStage"] = "native playback checked; before background session creation"
            Self.record(report, test: self)
            let delegate = BoundedHLSDownloadDelegate()
            let configuration = URLSessionConfiguration.background(withIdentifier: "com.streamify.native-hls-probe.\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = false
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 8
            let session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let download = AVAssetDownloadConfiguration(asset: asset, title: "Bounded native HLS feasibility")
            download.primaryContentConfiguration.variantQualifiers = [AVAssetVariantQualifier(variant: fullHD)]
            download.primaryContentConfiguration.mediaSelections = [selection]
            let task = session.makeAssetDownloadTask(downloadConfiguration: download)
            task.taskDescription = "diagnostic-only-cancel-before-full-episode"
            task.resume()
            let downloadDeadline = Date().addingTimeInterval(4)
            while Date() < downloadDeadline && !delegate.finished {
                if task.countOfBytesReceived >= 2 * 1024 * 1024 { delegate.stop(task, reason: "early byte budget") }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            delegate.stop(task, reason: "short diagnostic deadline")
            session.invalidateAndCancel()
            let finishDeadline = Date().addingTimeInterval(2)
            while !delegate.finished && Date() < finishDeadline { try await Task.sleep(nanoseconds: 25_000_000) }
            report["download"] = delegate.summary(task: task)
            delegate.removeOnlyOwnedPartialPackage()
            guard delegate.accepted else { throw DiagnosticError.message("Native downloader did not resolve or load media within the bounded probe") }
            guard task.countOfBytesReceived <= Self.maximumObservedMediaBytes else { throw DiagnosticError.message("Native downloader exceeded the diagnostic byte budget") }
            report["feasibility"] = "Native video+audio and download-task acceptance; complete offline persistence remains untested"
        } catch {
            report["failurePhase"] = phase
            report["error"] = Self.errorChain(error)
        }
        Self.record(report, test: self)
        XCTAssertNil(report["error"], "Native HLS feasibility failed at \(phase): \(report["error"] ?? "unknown")")
    }

    private struct Source { let master: URL; let summary: [String: Any] }
    private enum DiagnosticError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }

    private static func freshSource() async throws -> Source {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = URL(string: "https://vixsrc.to/api/tv/124364/1/1")!
        let data = try await metadata(api, session: session, referer: page, limit: 32 * 1024)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let src = object["src"] as? String, let embed = URL(string: src, relativeTo: origin)?.absoluteURL,
              embed.host == origin.host else { throw DiagnosticError.message("Public API did not advertise a same-origin embed") }
        let html = String(decoding: try await metadata(embed, session: session, referer: page, limit: 256 * 1024), as: UTF8.self)
        guard !html.contains("cf-chl-") && !html.contains("challenge-platform") else { throw DiagnosticError.message("Challenge barrier; no bypass") }
        let expression = #"window\.masterPlaylist\s*=\s*\{\s*params:\s*\{([\s\S]*?)\}\s*,\s*url:\s*['"]([^'"]+)['"]"#
        guard let fields = matches(expression, html).first, fields.count == 2,
              let raw = URL(string: fields[1].replacingOccurrences(of: "\\/", with: "/")),
              var master = URLComponents(url: raw, resolvingAgainstBaseURL: false) else { throw DiagnosticError.message("No plain published masterPlaylist metadata") }
        var query = master.queryItems ?? []
        for pair in matches(#"['"]([^'"]+)['"]\s*:\s*['"]([^'"]*)['"]"#, fields[0]) where pair.count == 2 && !pair[1].isEmpty {
            query.append(URLQueryItem(name: pair[0], value: pair[1]))
        }
        let embedded = URLComponents(url: embed, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let cdn = embedded.first(where: { $0.name == "cdn" })?.value { query.append(URLQueryItem(name: "cdn", value: cdn)) }
        query.append(URLQueryItem(name: "h", value: "1"))
        query.append(URLQueryItem(name: "lang", value: embedded.first(where: { $0.name == "lang" })?.value ?? "en"))
        master.queryItems = query
        guard let url = master.url else { throw DiagnosticError.message("Invalid published master URL") }
        let playlist = String(decoding: try await metadata(url, session: session, referer: embed, limit: 256 * 1024), as: UTF8.self)
        guard playlist.hasPrefix("#EXTM3U") else { throw DiagnosticError.message("Source did not return an HLS master") }
        var keyHosts = Set<String>()
        try validateProtection(playlist, base: url, keyHosts: &keyHosts)
        let lines = playlist.components(separatedBy: .newlines)
        var video: URL?, english: URL?
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#EXT-X-STREAM-INF:"), line.contains("RESOLUTION=1920x1080"),
               index + 1 < lines.count { video = URL(string: lines[index + 1], relativeTo: url)?.absoluteURL }
            if line.hasPrefix("#EXT-X-MEDIA:"), line.contains("TYPE=AUDIO"),
               line.contains("LANGUAGE=\"eng\"") || line.contains("LANGUAGE=\"en\"") {
                if let uri = matches(#"URI="([^"]+)""#, line).first?.first { english = URL(string: uri, relativeTo: url)?.absoluteURL }
            }
        }
        guard let video, let english else { throw DiagnosticError.message("Master lacks an advertised 1080p video or English audio rendition") }
        for rendition in [video, english] {
            let text = String(decoding: try await metadata(rendition, session: session, referer: embed, limit: 256 * 1024), as: UTF8.self)
            guard text.hasPrefix("#EXTM3U"), text.contains("#EXT-X-ENDLIST") else { throw DiagnosticError.message("Rendition is not complete VOD") }
            try validateProtection(text, base: rendition, keyHosts: &keyHosts)
        }
        return Source(master: url, summary: ["canonicalPath": url.path, "advertisedVideo": "1920x1080",
            "englishAudioAdvertised": true, "endList": true, "allowedProtection": "NONE or AES-128 identity only",
            "keyHosts": keyHosts.sorted(), "metadataProviderHeaders": true])
    }

    private static func metadata(_ url: URL, session: URLSession, referer: URL, limit: Int) async throws -> Data {
        try allowed(url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await session.bytes(for: request, delegate: ManualHLSMetadataRedirectPolicy())
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DiagnosticError.message("Ordinary public metadata HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0); no retry/bypass")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw DiagnosticError.message("Metadata byte bound") }
            data.append(byte)
        }
        return data
    }

    fileprivate static func allowed(_ url: URL) throws {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443,
              url.host != "surge.flooderrr.store", !url.path.lowercased().contains("/proxy") else {
            throw DiagnosticError.message("Insecure, authenticated, or relay URL is outside this diagnostic")
        }
    }
    private static func validateProtection(_ text: String, base: URL, keyHosts: inout Set<String>) throws {
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                let method = matches(#"METHOD=([^,\r\n]+)"#, line).first?.first ?? ""
                let format = matches(#"KEYFORMAT="([^"]+)""#, line).first?.first ?? "identity"
                guard ["NONE", "AES-128"].contains(method), format == "identity" else { throw DiagnosticError.message("DRM or unsupported protection barrier; no key/license request") }
                if method == "AES-128", let uri = matches(#"URI="([^"]+)""#, line).first?.first,
                   let key = URL(string: uri, relativeTo: base)?.absoluteURL {
                    try allowed(key); if let host = key.host { keyHosts.insert(host) }
                }
            }
            if !line.isEmpty && !line.hasPrefix("#"), let source = URL(string: line, relativeTo: base)?.absoluteURL { try allowed(source) }
        }
    }
    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (1..<match.numberOfRanges).map { source.substring(with: match.range(at: $0)) }
        }
    }
    private static func fourCC(_ code: FourCharCode) -> String {
        String(decoding: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], as: UTF8.self)
    }
    fileprivate static func errorChain(_ error: Error) -> String {
        var result: [String] = [], current: NSError? = error as NSError
        for _ in 0..<6 {
            guard let value = current else { break }
            let safe = value.localizedDescription.replacingOccurrences(of: #"https?://\S+"#, with: "[source URL]", options: .regularExpression)
            result.append("\(value.domain):\(value.code) \(safe)")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result.joined(separator: " → ")
    }
    private static func record(_ report: [String: Any], test: XCTestCase) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Native HLS feasibility"; attachment.lifetime = .keepAlways
        test.add(attachment)
        print("NATIVE_HLS_DIAGNOSTIC \(json)")
    }
}

private final class ManualHLSMetadataRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? VixSrcNativeHLSDiagnosticsTests.allowed(url)) != nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}

private final class BoundedHLSDownloadDelegate: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false, completed = false
    private var loaded = 0.0
    private var reason = "", failure = ""
    private var destination: URL?
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return completed }
    var accepted: Bool { lock.lock(); defer { lock.unlock() }; return resolved || loaded > 0 }
    func stop(_ task: AVAssetDownloadTask, reason: String) {
        lock.lock(); if self.reason.isEmpty { self.reason = reason }; lock.unlock()
        task.cancel()
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
        lock.lock(); resolved = true; lock.unlock()
        stop(assetDownloadTask, reason: "media selection resolved; stop before full episode")
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        lock.lock(); loaded = loadedTimeRanges.reduce(0) { $0 + max(0, $1.timeRangeValue.duration.seconds) }; lock.unlock()
        stop(assetDownloadTask, reason: "first loaded time range; stop before full episode")
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        lock.lock(); destination = location; lock.unlock()
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock(); destination = location; lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); completed = true
        if let error, (error as NSError).code != NSURLErrorCancelled { failure = VixSrcNativeHLSDiagnosticsTests.errorChain(error) }
        lock.unlock()
    }
    func summary(task: AVAssetDownloadTask) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["selectionResolved": resolved, "loadedSeconds": loaded.isFinite ? loaded : 0,
            "observedBytes": max(0, task.countOfBytesReceived), "cancelReason": reason,
            "callbackCompleted": completed, "error": failure, "completeOfflineAsset": false]
    }
    func removeOnlyOwnedPartialPackage() {
        lock.lock(); let file = destination; lock.unlock()
        guard let file, file.isFileURL, file.pathExtension == "movpkg" else { return }
        let target = file.standardizedFileURL.resolvingSymlinksInPath()
        let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard target.path.hasPrefix(library) else { return }
        try? FileManager.default.removeItem(at: target)
    }
}
