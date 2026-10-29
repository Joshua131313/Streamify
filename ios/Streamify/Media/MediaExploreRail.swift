import SwiftUI

/// Keep the presentation owner outside recycled horizontal poster cells. A
/// tapped discovery poster has one stable destination and its own zoom anchor.
struct MediaExploreRail: View {
    let identifier: String
    let items: [MediaItem]
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var transition
    @State private var selected: MediaItem?
    @State private var watching: MediaItem?
    @State private var playbackOrigin: MediaPlaybackOrigin?

    var body: some View {
        if #available(iOS 18, *) {
            rail.fullScreenCover(item: $selected) { media in
                if reduceMotion { destination(media) }
                else { destination(media).navigationTransition(.zoom(sourceID: media.key, in: transition)) }
            }
            .fullScreenCover(item: $watching) { watchDestination($0) }
        } else {
            rail.sheet(item: $selected) { media in
                destination(media).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
            .fullScreenCover(item: $watching) { watchDestination($0) }
        }
    }

    private var rail: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(items, id: \.key) { media in
                    MediaPlaybackOriginCard { origin in
                    Button { selected = media } label: {
                        if #available(iOS 18, *) {
                            poster(media).matchedTransitionSource(id: media.key, in: transition)
                        } else { poster(media) }
                    }
                    .buttonStyle(HapticCardButtonStyle(cornerRadius: 8))
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("\(media.title), \(media.kind.singular). Open details")
                    .accessibilityIdentifier("explore-\(identifier)-media-\(media.key)")
                    .contextMenu {
                        Button("Details", systemImage: "info.circle") { selected = media }
                        Button("Watch", systemImage: "play.fill") { playbackOrigin = origin; watching = media }
                        if !library.isSaved(media) {
                            Button("Add to My list", systemImage: "plus") { library.toggleSaved(media) }
                        }
                        ShareLink(item: URL(string: media.kind == .anime
                            ? "https://anilist.co/anime/\(media.id)" : "https://www.themoviedb.org/\(media.kind.rawValue)/\(media.id)")!)
                        if library.isSaved(media) {
                            Button("Remove from My list", systemImage: "bookmark.slash", role: .destructive) { library.toggleSaved(media) }
                        }
                    }
                    }
                }
            }.padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("home-explore-\(identifier)")
    }

    private func poster(_ media: MediaItem) -> some View {
        PosterContent(media: media).frame(width: sizeClass == .regular ? 152 : 112).clipped().contentShape(Rectangle())
    }

    private func destination(_ media: MediaItem) -> some View {
        NavigationStack { MediaDetailView(media: media) }.presentationBackground(AppTheme.canvas)
    }

    private func watchDestination(_ media: MediaItem) -> some View {
        let entry = library.history.first { $0.media.key == media.key }
        return MediaPlayerView(media: media, season: entry?.season ?? 1, episode: entry?.episode ?? 1, origin: playbackOrigin)
    }
}
