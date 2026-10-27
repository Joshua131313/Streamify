import AVFoundation
import Foundation

/// System-managed HLS packages stay at the location supplied by AVFoundation.
/// Store a path relative to this app's container because its UUID can change.
enum HLSDownloadedPackages {
    static func relativePath(of location: URL, home: URL = URL(fileURLWithPath: NSHomeDirectory())) throws -> String {
        let root = home.standardizedFileURL.resolvingSymlinksInPath()
        let package = location.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = normalizedPath(root) + "/"
        let path = normalizedPath(package)
        guard location.isFileURL, path.hasPrefix(prefix) else {
            reportRejectedLocation(location, home: root)
            throw OfflineVideoError.missingFile
        }
        let relative = String(path.dropFirst(prefix.count))
        guard let restored = fileURL(for: relative, home: root), normalizedPath(restored) == path else {
            reportRejectedLocation(location, home: root)
            throw OfflineVideoError.missingFile
        }
        return relative
    }

    static func fileURL(for relativePath: String, home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL? {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.first == "Library", !relativePath.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              URL(fileURLWithPath: relativePath).pathExtension.lowercased() == "movpkg" else { return nil }
        let library = home.appendingPathComponent("Library", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let package = home.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard package.path.hasPrefix(library.path + "/"), package != library else { return nil }
        return package
    }

    static func remove(relativePath: String) throws {
        guard let package = fileURL(for: relativePath) else { throw OfflineVideoError.missingFile }
        if FileManager.default.fileExists(atPath: package.path) { try FileManager.default.removeItem(at: package) }
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func reportRejectedLocation(_ location: URL, home: URL) {
        #if DEBUG
        let path = normalizedPath(location), root = normalizedPath(home)
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let shared = zip(location.pathComponents, home.pathComponents).prefix(while: { $0.0 == $0.1 }).count
        func redactedShape(_ url: URL) -> String {
            let parts = url.pathComponents
            return parts.enumerated().map { index, part in
                if index > 0, parts[index - 1] == "Users" { return "[user]" }
                if part.lowercased().hasSuffix(".movpkg") { return "[asset].movpkg" }
                return part.replacingOccurrences(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
                    with: "[id]", options: .regularExpression)
            }.joined(separator: "/")
        }
        let shape: [String: Any] = ["isFileURL": location.isFileURL,
            "directoryHint": location.hasDirectoryPath, "extension": location.pathExtension,
            "insideAppHome": path.hasPrefix(root + "/"),
            "insideAppLibrary": path.hasPrefix(root + "/Library/"),
            "homeRelativeTopDirectory": path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1).split(separator: "/").first ?? "") : "outside",
            "componentCount": location.pathComponents.count,
            "locationShape": redactedShape(location), "homeShape": redactedShape(home),
            "fileManagerHomeShape": redactedShape(FileManager.default.homeDirectoryForCurrentUser),
            "libraryShape": library.map(redactedShape) ?? "missing", "commonPrefixComponentCount": shared,
            "insideFileManagerLibrary": library.map { path.hasPrefix(normalizedPath($0) + "/") } ?? false,
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown"]
        if let data = try? JSONSerialization.data(withJSONObject: shape, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print("HLS_PACKAGE_POLICY_DIAGNOSTIC \(text)") }
        #endif
    }
}

enum HLSDownloadProgress {
    /// Loaded time ranges can overlap. Count their union, clipped to the
    /// expected interval, instead of summing duplicate media time as bytes.
    static func fraction(loaded: [CMTimeRange], expected: CMTimeRange) -> Double? {
        let origin = expected.start.seconds, duration = expected.duration.seconds
        guard origin.isFinite, duration.isFinite, duration > 0 else { return nil }
        let end = origin + duration
        guard end.isFinite else { return nil }
        let ranges = loaded.compactMap { range -> (Double, Double)? in
            let start = range.start.seconds, length = range.duration.seconds
            guard start.isFinite, length.isFinite, length > 0, (start + length).isFinite else { return nil }
            let lower = max(origin, start), upper = min(end, start + length)
            return upper > lower ? (lower, upper) : nil
        }.sorted { $0.0 < $1.0 }
        var total = 0.0, pending: (Double, Double)?
        for range in ranges {
            if let current = pending {
                if range.0 <= current.1 { pending = (current.0, max(current.1, range.1)) }
                else { total += current.1 - current.0; pending = range }
            } else { pending = range }
        }
        if let pending { total += pending.1 - pending.0 }
        return min(1, max(0, total / duration))
    }
}

/// Package validation is intentionally separate from the progressive MP4
/// validator: HLS assets need not expose materialized tracks or I-frame images.
enum OfflineHLSValidation {
    struct Result {
        let asset: AVURLAsset
        let duration: Double
        let audioGroup: AVMediaSelectionGroup
        let audioOption: AVMediaSelectionOption
    }

    static func isRequestedLanguage(_ option: AVMediaSelectionOption, language: String) -> Bool {
        let requested = language.lowercased()
        let actual = option.extendedLanguageTag?.lowercased() ?? option.locale?.language.languageCode?.identifier.lowercased() ?? ""
        return !requested.isEmpty && !actual.isEmpty && (actual == requested || actual.prefix(2) == requested.prefix(2))
    }

    static func validate(_ location: URL, quality: Int?, audioLanguage: String = "en", timeout: TimeInterval = 12) async throws -> Result {
        try Task.checkCancellation()
        _ = try HLSDownloadedPackages.relativePath(of: location)
        guard let values = try? location.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true,
              FileManager.default.isReadableFile(atPath: location.path) else { throw OfflineVideoError.missingFile }
        let asset = AVURLAsset(url: location)
        do {
            return try await withThrowingTaskGroup(of: Result.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        // A local package location alone also exists for a
                        // cancelled task. It is never proof of completion.
                        #if DEBUG
                        print("HLS_LOCAL_CACHE_DIAGNOSTIC present=\(asset.assetCache != nil) playableOffline=\(asset.assetCache?.isPlayableOffline == true)")
                        #endif
                        guard let cache = asset.assetCache, cache.isPlayableOffline else { throw OfflineVideoError.damagedFile }
                        let (playable, duration) = try await asset.load(.isPlayable, .duration)
                        #if DEBUG
                        let protected = try? await asset.load(.hasProtectedContent)
                        print("HLS_LOCAL_METADATA_DIAGNOSTIC playable=\(playable) protected=\(String(describing: protected)) duration=\(duration.seconds)")
                        #endif
                        // This path accepts only system-owned packages from
                        // the verified clear/identity-AES128 VOD pipeline. The
                        // offline cache and cached audio prove availability;
                        // encryption alone is not an unsupported DRM verdict.
                        guard playable else { throw OfflineVideoError.unplayable }
                        guard duration.seconds.isFinite, duration.seconds > 0 else { throw OfflineVideoError.damagedFile }
                        guard let audio = try await asset.loadMediaSelectionGroup(for: .audible),
                              let english = cache.mediaSelectionOptions(in: audio).first(where: {
                                  $0.isPlayable && isRequestedLanguage($0, language: audioLanguage)
                              }) else { throw OfflineVideoError.incompatible }
                        if let quality {
                            let variants = try await asset.load(.variants)
                            guard variants.contains(where: { variant in
                                guard let size = variant.videoAttributes?.presentationSize,
                                      size.width.isFinite, size.height.isFinite,
                                      size.width > 0, size.height > 0,
                                      size.width <= 65_535, size.height <= 65_535 else { return false }
                                return (try? OfflineVideoValidation.requireQuality(quality,
                                    width: Int(size.width.rounded()), height: Int(size.height.rounded()))) != nil
                            }) else { throw OfflineVideoError.qualityMismatch }
                        }
                        try Task.checkCancellation()
                        return Result(asset: asset, duration: duration.seconds, audioGroup: audio, audioOption: english)
                    } onCancel: { asset.cancelLoading() }
                }
                group.addTask {
                    let seconds = timeout.isFinite ? min(60, max(0.1, timeout)) : 12
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw OfflineVideoError.unplayable
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw OfflineVideoError.unplayable }
                return result
            }
        } catch {
            asset.cancelLoading()
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw OfflineVideoError.classify(error)
        }
    }
}
