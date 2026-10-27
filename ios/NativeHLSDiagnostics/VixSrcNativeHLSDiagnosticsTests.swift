import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit
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
                do { try await Task.sleep(nanoseconds: 50_000_000_000); asset.cancelLoading() }
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
            report["native1080VariantPeakBitRate"] = fullHD.peakBitRate ?? 0
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
            report["englishAudioOptionPlayable"] = english.isPlayable
            report["englishAudioOptionSubTypes"] = english.mediaSubTypes.map { Self.fourCC($0.uint32Value) }
            // HLS does not guarantee that AVAsset exposes materialized audio
            // tracks. This capability/selection evidence remains separate
            // from track metadata and does not claim decoded PCM samples.
            report["actualDecodedAudioPCMProven"] = false

            phase = "native master playback"
            var playbackFailure: String?
            var playbackObservedBytes: Int64 = 0
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .moviePlayback)
                try audioSession.setActive(true)
                defer { try? audioSession.setActive(false, options: .notifyOthersOnDeactivation) }
                report["audioSessionActive"] = true
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 1
                // These preferences are upper bounds, not a promise that adaptive
                // playback selects 1080p. Actual decoded pixels are checked below.
                // Zero is AVPlayer's default (no throughput ceiling). A nil
                // variant bitrate must not accidentally become a 1bps limit.
                item.preferredPeakBitRate = max(0, fullHD.peakBitRate ?? 0)
                item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
                report["playbackResolutionPreferenceIsCeiling"] = true
                item.select(english, in: audioGroup)
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
                    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                item.add(output)
                let player = AVPlayer(playerItem: item)
                player.isMuted = false
                player.volume = 0.1
                player.allowsExternalPlayback = false
                player.automaticallyWaitsToMinimizeStalling = false
                guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first,
                      let hostView = window.rootViewController?.view else {
                    throw DiagnosticError.message("Research host did not expose a visible playback surface")
                }
                let playerLayer = AVPlayerLayer(player: player)
                playerLayer.frame = hostView.bounds
                playerLayer.videoGravity = .resizeAspect
                hostView.layer.addSublayer(playerLayer)
                report["visiblePlayerLayerAttached"] = !window.isHidden && !hostView.isHidden
                defer { player.pause(); player.replaceCurrentItem(with: nil); playerLayer.removeFromSuperlayer() }
                var pixelWidth = 0, pixelHeight = 0
                var playbackSeconds = 0.0
                var transferred: Int64 = 0
                var transitions: [[String: Any]] = []
                var previousState = ""
                let readyDeadline = Date().addingTimeInterval(10)
                while item.status == .unknown && Date() < readyDeadline {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                report["itemStatusBeforePlay"] = item.status.rawValue
                if item.status == .readyToPlay {
                    // Select again once the item is ready; selecting before its
                    // media group has loaded is not used as evidence of playback.
                    item.select(english, in: audioGroup)
                    player.playImmediately(atRate: 1)
                }
                let deadline = Date().addingTimeInterval(20)
                while Date() < deadline {
                    try Task.checkCancellation()
                    let state = "\(item.status.rawValue):\(player.timeControlStatus.rawValue):\(player.rate):\(player.reasonForWaitingToPlay?.rawValue ?? "")"
                    if state != previousState {
                        transitions.append(Self.playbackState(player, item: item))
                        previousState = state
                    }
                    if item.status == .failed { break }
                    if item.status == .readyToPlay && player.rate == 0 && playbackSeconds == 0 {
                        player.playImmediately(atRate: 1)
                    }
                    let time = item.currentTime()
                    if time.seconds.isFinite { playbackSeconds = time.seconds }
                    if output.hasNewPixelBuffer(forItemTime: time),
                       let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                        pixelWidth = CVPixelBufferGetWidth(frame); pixelHeight = CVPixelBufferGetHeight(frame)
                    }
                    transferred = item.accessLog()?.events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) } ?? 0
                    if transferred >= Self.maximumObservedMediaBytes { break }
                    if pixelWidth == 1920 && pixelHeight == 1080 && playbackSeconds >= 1 { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                // Capture state before pausing, otherwise paused/rate-zero hides
                // the reason that playback stalled in the native player.
                report["playbackFinalState"] = Self.playbackState(player, item: item)
                report["playbackStateTransitions"] = transitions
                report["playerLayerReadyForDisplay"] = playerLayer.isReadyForDisplay
                report["nativePlayerErrors"] = item.errorLog()?.events.map { event in
                    ["status": event.errorStatusCode, "domain": event.errorDomain,
                     "comment": Self.redact(event.errorComment ?? "")] as [String: Any]
                } ?? []
                if let error = item.error { report["nativePlayerItemError"] = Self.errorChain(error) }
                player.pause()
                report["pixelWidth"] = pixelWidth; report["pixelHeight"] = pixelHeight
                report["actualVideoFrame"] = pixelWidth > 0 && pixelHeight > 0
                report["actualPreview1080"] = pixelWidth == 1920 && pixelHeight == 1080
                report["native1080PlaybackProven"] = pixelWidth == 1920 && pixelHeight == 1080 && playbackSeconds >= 1
                report["playbackSeconds"] = playbackSeconds
                report["playbackObservedBytes"] = transferred
                report["playbackByteBudgetReached"] = transferred >= Self.maximumObservedMediaBytes
                playbackObservedBytes = transferred
                let selectedAudioLanguage = item.currentMediaSelection.selectedMediaOption(in: audioGroup)?.extendedLanguageTag ?? "unknown"
                report["selectedEnglishAudio"] = selectedAudioLanguage
                report["selectedEnglishAudioPlayable"] = item.currentMediaSelection.selectedMediaOption(in: audioGroup)?.isPlayable ?? false
                let assetAudioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                let materializedAudioTracks = item.tracks.compactMap { $0.assetTrack }.filter { $0.mediaType == .audio }
                let audioTracks = assetAudioTracks + materializedAudioTracks
                report["nativeAssetAudioTrackCount"] = assetAudioTracks.count
                report["nativeItemAudioTrackCount"] = materializedAudioTracks.count
                report["nativeAudioTrackCount"] = Set(audioTracks.map { $0.trackID }).count
                report["nativeItemTracks"] = item.tracks.map { track in
                    ["enabled": track.isEnabled, "mediaType": track.assetTrack?.mediaType.rawValue ?? "unmaterialized",
                     "trackID": track.assetTrack?.trackID ?? 0] as [String: Any]
                }
                var audioDecodable = false
                var audioCodecs: [String] = []
                for track in audioTracks {
                    if (try? await track.load(.isDecodable)) == true { audioDecodable = true }
                    for format in (try? await track.load(.formatDescriptions)) ?? [] {
                        audioCodecs.append(Self.fourCC(CMFormatDescriptionGetMediaSubType(format)))
                    }
                }
                report["nativeAudioDecodable"] = audioDecodable
                report["nativeAudioCodecs"] = Array(Set(audioCodecs)).sorted()
                guard pixelWidth > 0, pixelHeight > 0, playbackSeconds >= 1,
                      selectedAudioLanguage.lowercased().hasPrefix("en"), english.isPlayable,
                      item.currentMediaSelection.selectedMediaOption(in: audioGroup)?.isPlayable == true else {
                    throw DiagnosticError.message("Native player did not demonstrate real advancing video with a selected playable English audio option within the bounded preview")
                }
                report["nativePlaybackProven"] = true
            } catch {
                let failure = Self.errorChain(error)
                playbackFailure = failure
                report["playbackFailure"] = failure
                report["nativePlaybackProven"] = false
            }

            phase = "bounded native download acceptance"
            // Download selection is an independent experiment. Adaptive
            // playback starting at 480p is not grounds to skip Apple's exact
            // 1080p download qualifier and media-selection resolution.
            report["probeStage"] = "playback observation complete; independent download acceptance starts"
            Self.record(report, test: self)
            guard playbackObservedBytes < Self.maximumObservedMediaBytes else {
                throw DiagnosticError.message("No remaining combined byte budget for independent download observation")
            }
            let delegate = BoundedHLSDownloadDelegate(audioGroup: audioGroup)
            let configuration = URLSessionConfiguration.background(withIdentifier: "com.streamify.native-hls-probe.\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = false
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 15
            let session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let download = AVAssetDownloadConfiguration(asset: asset, title: "Bounded native HLS feasibility")
            download.primaryContentConfiguration.variantQualifiers = [AVAssetVariantQualifier(variant: fullHD)]
            download.primaryContentConfiguration.mediaSelections = [selection]
            let task = session.makeAssetDownloadTask(downloadConfiguration: download)
            task.taskDescription = "diagnostic-only-cancel-before-full-episode"
            task.resume()
            let downloadDeadline = Date().addingTimeInterval(10)
            while Date() < downloadDeadline && !delegate.finished {
                if task.countOfBytesReceived >= min(2 * 1024 * 1024, max(0, Self.maximumObservedMediaBytes - playbackObservedBytes)) {
                    delegate.stop(task, reason: "early combined byte budget")
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            delegate.stop(task, reason: "short diagnostic deadline")
            session.invalidateAndCancel()
            let finishDeadline = Date().addingTimeInterval(2)
            while !delegate.finished && Date() < finishDeadline { try await Task.sleep(nanoseconds: 25_000_000) }
            report["download"] = delegate.summary(task: task)
            report["combinedObservedMediaBytes"] = playbackObservedBytes + max(0, task.countOfBytesReceived)
            delegate.removeOnlyOwnedPartialPackage()
            guard delegate.accepted else { throw DiagnosticError.message("Native downloader did not confirm the exact 1080p variant and English audio selection within the bounded probe") }
            guard playbackObservedBytes + max(0, task.countOfBytesReceived) <= Self.maximumObservedMediaBytes else { throw DiagnosticError.message("Native downloader exceeded the combined diagnostic byte budget") }
            report["nativeDownloadAccepted"] = true
            if let playbackFailure {
                phase = "native master playback (download acceptance recorded independently)"
                throw DiagnosticError.message(playbackFailure)
            }
            report["feasibility"] = "Real advancing native video with playable selected English audio; exact 1080p/English download-task selection accepted. Decoded audio PCM and complete offline persistence remain unproven."
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
    @MainActor
    private static func playbackState(_ player: AVPlayer, item: AVPlayerItem) -> [String: Any] {
        let time = item.currentTime().seconds
        return ["itemStatus": item.status.rawValue, "timeControlStatus": player.timeControlStatus.rawValue,
            "waitingReason": player.reasonForWaitingToPlay?.rawValue ?? "none", "rate": player.rate,
            "currentSeconds": time.isFinite ? time : 0,
            "bufferEmpty": item.isPlaybackBufferEmpty, "bufferFull": item.isPlaybackBufferFull,
            "likelyToKeepUp": item.isPlaybackLikelyToKeepUp,
            "loadedTimeRanges": item.loadedTimeRanges.map { value in
                let range = value.timeRangeValue
                return ["start": range.start.seconds.isFinite ? range.start.seconds : 0,
                        "duration": range.duration.seconds.isFinite ? range.duration.seconds : 0]
            },
            "accessEvents": item.accessLog()?.events.map { event in
                ["bytes": max(0, event.numberOfBytesTransferred), "stalls": event.numberOfStalls,
                 "observedBitRate": event.observedBitrate.isFinite ? event.observedBitrate : 0,
                 "indicatedBitRate": event.indicatedBitrate.isFinite ? event.indicatedBitrate : 0] as [String: Any]
            } ?? []]
    }
    private static func redact(_ value: String) -> String {
        value.replacingOccurrences(of: #"https?://\S+"#, with: "[source URL]", options: .regularExpression)
    }
    fileprivate static func errorChain(_ error: Error) -> String {
        var result: [String] = [], current: NSError? = error as NSError
        for _ in 0..<6 {
            guard let value = current else { break }
            let safe = redact(value.localizedDescription)
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
    private let audioGroup: AVMediaSelectionGroup
    private var resolved = false, completed = false
    private var selectedAudio = "unknown"
    private var selectedVariants: [[String: Int]] = []
    private var loaded = 0.0
    private var reason = "", failure = ""
    private var destination: URL?
    init(audioGroup: AVMediaSelectionGroup) { self.audioGroup = audioGroup }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return completed }
    var accepted: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved && selectedAudio.lowercased().hasPrefix("en") && !selectedVariants.isEmpty
            && selectedVariants.allSatisfy { $0["width"] == 1920 && $0["height"] == 1080 }
    }
    func stop(_ task: AVAssetDownloadTask, reason: String) {
        lock.lock(); if self.reason.isEmpty { self.reason = reason }; lock.unlock()
        task.cancel()
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
        lock.lock(); resolved = true
        selectedAudio = resolvedMediaSelection.selectedMediaOption(in: audioGroup)?.extendedLanguageTag ?? "unknown"
        lock.unlock()
        if accepted { stop(assetDownloadTask, reason: "exact variant and English selection resolved; stop before full episode") }
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadVariants variants: [AVAssetVariant]) {
        lock.lock()
        selectedVariants = variants.compactMap { variant in
            guard let size = variant.videoAttributes?.presentationSize else { return nil }
            return ["width": Int(size.width), "height": Int(size.height)]
        }
        lock.unlock()
        if accepted { stop(assetDownloadTask, reason: "exact variant and English selection resolved; stop before full episode") }
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
            "selectedEnglishAudio": selectedAudio, "selectedVariants": selectedVariants,
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
