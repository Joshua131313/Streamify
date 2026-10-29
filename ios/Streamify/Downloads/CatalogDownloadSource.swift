import Foundation

enum CatalogDownloadTransport: String, Codable, Sendable {
    case progressiveFile
    case hlsVOD
}

/// Created only after checking the exact returned VOD video and audio
/// manifests. Apple handles ordinary identity AES-128; no key bytes are read.
struct HLSDownloadSource: Sendable {
    enum Protection: String, Codable, Sendable { case clearOrIdentityAES128 }
    let masterURL: URL
    let quality: Int
    let audioLanguage: String
    let protection: Protection
    let isVOD: Bool
}

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
    var transport: CatalogDownloadTransport = .progressiveFile
    var audioLanguage: String? = nil
    var hlsSource: HLSDownloadSource? = nil
    var providerID: String? = nil

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
            return "The selected quality cannot be played by this device. Choose another quality or watch online."
        }
    }
}
