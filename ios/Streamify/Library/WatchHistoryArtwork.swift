import SwiftUI

/// Repairs sparse saved metadata and tries the poster if a backdrop disappears.
struct WatchHistoryArtwork: View {
    let media: MediaItem
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @State private var attemptedKey: String?

    var body: some View {
        RemoteArtwork(url: media.backdropURL,
            fallbackURLs: [media.posterURL].compactMap { $0 },
            onFailure: { Task { await repair(force: true) } })
            .task(id: "\(media.key)|\(settings.tmdbToken)") {
                if catalogImageURL(media.backdropPath) == nil || catalogImageURL(media.posterPath) == nil {
                    await repair(force: false)
                }
            }
    }

    @MainActor private func repair(force: Bool) async {
        let key = "\(media.key)|\(settings.tmdbToken)"
        guard attemptedKey != key, !settings.tmdbToken.isEmpty else { return }
        attemptedKey = key
        do {
            let metadata = try await settings.client.reloading(force).mediaMetadata(media)
            try Task.checkCancellation()
            library.repairHistoryArtwork(metadata)
        } catch {
            if Task.isCancelled { attemptedKey = nil }
            // A failed image lookup must not interrupt resume or change watch progress.
        }
    }
}
