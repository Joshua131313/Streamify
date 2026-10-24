import Foundation
import AVFoundation

enum OfflineVideoError: LocalizedError, Hashable {
    case missingFile, damagedFile, noVideo, incompatible, unplayable, protectedContent

    var errorDescription: String? {
        switch self {
        case .missingFile: return "The local video file is missing or could not be opened."
        case .damagedFile: return "The downloaded file is incomplete, damaged, or could not be read."
        case .noVideo: return "This file does not contain a video track."
        case .incompatible: return "This file contains a video or audio track that this iPhone cannot play."
        case .unplayable: return "The iOS player could not play this file."
        case .protectedContent: return "This file requires protected playback that is not available for this offline download."
        }
    }
    var recoverySuggestion: String? {
        switch self {
        case .missingFile, .damagedFile: return "Download the video again, or import a complete copy from Files."
        case .noVideo: return "Choose a movie file with a video track instead of an audio-only file."
        case .incompatible, .unplayable:
            return "Try another download source or an H.264 video with AAC audio in an MP4 file. Changing the filename or resolution alone may not fix its encoding."
        case .protectedContent: return "Choose an unprotected download that you are allowed to save and play offline."
        }
    }
    var isCompatibilityIssue: Bool { self == .incompatible || self == .unplayable || self == .protectedContent }
    var downloadMessage: String { [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ") }

    static func classify(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        var current = error as NSError?
        for _ in 0..<6 {
            guard let item = current else { break }
            if item.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError].contains(item.code) {
                return .missingFile
            }
            if item.domain == AVFoundationErrorDomain {
                switch item.code {
                case AVError.Code.decoderNotFound.rawValue: return .incompatible
                case AVError.Code.contentIsProtected.rawValue: return .protectedContent
                case AVError.Code.fileFailedToParse.rawValue: return .damagedFile
                default: break
                }
            }
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .unplayable
    }
}

/// Uses the device's real media capabilities; it does not convert or fully scan
/// the file and cannot promise that every later sample is intact or fast enough.
enum OfflineVideoValidation {
    struct Result {
        let asset: AVURLAsset
        let duration: Double
    }

    static func validate(_ url: URL) async throws -> Result {
        try Task.checkCancellation()
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { throw OfflineVideoError.missingFile }
        guard (values.fileSize ?? 0) > 0 else { throw OfflineVideoError.damagedFile }
        let asset = AVURLAsset(url: url)
        return try await withTaskCancellationHandler {
            do {
                return try await inspect(asset)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw OfflineVideoError.classify(error)
            }
        } onCancel: {
            asset.cancelLoading()
        }
    }

    /// Ask AVFoundation about the actual candidate before starting a complete
    /// download. Container names and HEVC tags alone do not determine support.
    /// AVFoundation loads the metadata it needs; a deadline and cancellation
    /// stop outstanding native asset loads. Local test assets use the same path.
    static func validateRemoteSource(_ url: URL, timeout: TimeInterval = 12) async throws {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        defer { asset.cancelLoading() }
        let seconds = timeout.isFinite ? min(60, max(0.05, timeout)) : 12
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        _ = try await inspect(asset)
                    } onCancel: { asset.cancelLoading() }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw OfflineSourceValidationError.unavailable
                }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // Only an explicit native unsupported/protected error establishes
            // compatibility. Network, rate limits and unknown metadata errors
            // must not be turned into a codec verdict or a lower-quality retry.
            throw OfflineSourceValidationError.classify(error)
        }
    }

    private static func inspect(_ asset: AVURLAsset) async throws -> Result {
        let (playable, duration, protected) = try await asset.load(.isPlayable, .duration, .hasProtectedContent)
        try Task.checkCancellation()
        guard !protected else { throw OfflineVideoError.protectedContent }
        let video = try await asset.loadTracks(withMediaType: .video)
        try Task.checkCancellation()
        guard !video.isEmpty else { throw OfflineVideoError.noVideo }
        guard duration.seconds.isFinite, duration.seconds > 0 else { throw OfflineVideoError.damagedFile }
        guard try await hasPlayableTrack(video) else { throw OfflineVideoError.incompatible }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        if !audio.isEmpty {
            guard try await hasPlayableTrack(audio) else { throw OfflineVideoError.incompatible }
        }
        guard playable else { throw OfflineVideoError.unplayable }
        try Task.checkCancellation()
        return Result(asset: asset, duration: duration.seconds)
    }

    private static func hasPlayableTrack(_ tracks: [AVAssetTrack]) async throws -> Bool {
        for track in tracks {
            let (decodable, playable) = try await track.load(.isDecodable, .isPlayable)
            try Task.checkCancellation()
            if decodable && playable { return true }
        }
        return false
    }
}

enum OfflineSourceValidationError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The download source could not be checked. Please try again later." }

    static func classify(_ error: Error) -> Error {
        if let error = error as? OfflineVideoError {
            if error.isCompatibilityIssue { return error }
            return Self.unavailable
        }
        var current = error as NSError?
        var unrecognizedFormat = false
        for _ in 0..<6 {
            guard let item = current else { break }
            // Transport failures take precedence over a media wrapper error.
            if item.domain == NSURLErrorDomain { return Self.unavailable }
            if item.domain == AVFoundationErrorDomain, item.code == AVError.Code.fileFormatNotRecognized.rawValue {
                unrecognizedFormat = true
            }
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        // A recognized native format rejection is a reason to inspect another
        // candidate. It does not establish which codec or container detail failed.
        if unrecognizedFormat { return OfflineVideoError.unplayable }
        let classified = OfflineVideoError.classify(error)
        if classified == .incompatible || classified == .protectedContent { return classified }
        return Self.unavailable
    }
}
