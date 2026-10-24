import SwiftUI

/// Keep the presentation owner outside recycled horizontal poster cells. A
/// tapped discovery poster has one stable destination and its own zoom anchor.
struct MediaExploreRail: View {
    let identifier: String
    let items: [MediaItem]
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var transition
    @State private var selected: MediaItem?

    var body: some View {
        if #available(iOS 18, *) {
            rail.fullScreenCover(item: $selected) { media in
                if reduceMotion { destination(media) }
                else { destination(media).navigationTransition(.zoom(sourceID: media.key, in: transition)) }
            }
        } else {
            rail.sheet(item: $selected) { media in
                destination(media).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(24)
            }
        }
    }

    private var rail: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(items, id: \.key) { media in
                    Button { selected = media } label: {
                        if #available(iOS 18, *) {
                            poster(media).matchedTransitionSource(id: media.key, in: transition)
                        } else { poster(media) }
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel("\(media.title), \(media.kind.singular). Open details")
                    .accessibilityIdentifier("explore-\(identifier)-media-\(media.key)")
                    .contextMenu {
                        Button(library.isSaved(media) ? "Remove from My list" : "Add to My list",
                            systemImage: library.isSaved(media) ? "checkmark" : "plus") { library.toggleSaved(media) }
                        ShareLink(item: URL(string: media.kind == .anime
                            ? "https://anilist.co/anime/\(media.id)" : "https://www.themoviedb.org/\(media.kind.rawValue)/\(media.id)")!)
                    }
                }
            }.padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("home-explore-\(identifier)")
    }

    private func poster(_ media: MediaItem) -> some View {
        PosterContent(media: media).frame(width: 112).clipped().contentShape(Rectangle())
    }

    private func destination(_ media: MediaItem) -> some View {
        NavigationStack { MediaDetailView(media: media) }.presentationBackground(AppTheme.canvas)
    }
}
