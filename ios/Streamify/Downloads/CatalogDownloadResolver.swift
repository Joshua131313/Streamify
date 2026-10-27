import Foundation

enum CatalogDownloadResolutionError: LocalizedError, Equatable {
    case unavailable(quality: Int)
    var errorDescription: String? {
        switch self {
        case .unavailable(let quality):
            return "No compatible \(quality)p download is available from the current sources. Please try again later or choose another quality."
        }
    }
}

/// Resolves another provider at the same requested resolution. The HLS and
/// progressive backends retain their own format checks and transfer owners.
struct CatalogDownloadResolver {
    typealias Source = (MediaItem, Int, Int, Int, Set<String>) async throws -> ResolvedMediaDownload
    private let hls: Source
    private let file: Source

    init(hls: Source? = nil, file: Source? = nil) {
        self.hls = hls ?? { media, season, episode, quality, excluded in
            try await VixSrcDownloadResolver().resolve(media: media, season: season, episode: episode,
                quality: quality, excludingSources: excluded)
        }
        self.file = file ?? { media, season, episode, quality, excluded in
            try await MediaDownloadResolver().resolve(media: media, season: season, episode: episode,
                maximumQuality: quality, excludingSources: excluded)
        }
    }

    func resolve(media: MediaItem, season: Int = 1, episode: Int = 1, maximumQuality: Int = 1080,
                 excludingSources: Set<String> = [], excludingProviders: Set<String> = []) async throws -> ResolvedMediaDownload {
        try Task.checkCancellation()
        guard media.id > 0, media.kind == .movie || media.kind == .tv else { throw MediaDownloadResolutionError.unsupportedMedia }
        guard media.kind != .tv || season > 0 && episode > 0 else { throw MediaDownloadResolutionError.invalidEpisode }
        guard [1080, 720, 480, 360].contains(maximumQuality) else { throw MediaDownloadResolutionError.qualityUnavailable }
        if [1080, 720].contains(maximumQuality), !excludingProviders.contains("VixSrc") {
            do {
                var source = try await hls(media, season, episode, maximumQuality, excludingSources)
                try Task.checkCancellation()
                guard source.quality == maximumQuality, source.transport == .hlsVOD,
                      let descriptor = source.hlsSource, descriptor.masterURL == source.url,
                      descriptor.quality == maximumQuality, descriptor.isVOD,
                      descriptor.audioLanguage.lowercased().hasPrefix("en"), !excludingSources.contains(source.url.absoluteString) else {
                    throw MediaDownloadResolutionError.invalidResponse
                }
                source.providerID = "VixSrc"
                return source
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
            }
        }
        if !excludingProviders.contains("VidLink") {
            do {
                var source = try await file(media, season, episode, maximumQuality, excludingSources)
                try Task.checkCancellation()
                guard source.quality == maximumQuality, source.transport == .progressiveFile,
                      !excludingSources.contains(source.url.absoluteString) else {
                    throw MediaDownloadResolutionError.invalidResponse
                }
                source.providerID = "VidLink"
                return source
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
            }
        }
        throw CatalogDownloadResolutionError.unavailable(quality: maximumQuality)
    }
}
