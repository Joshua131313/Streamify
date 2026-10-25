import SwiftUI

/// A distinct namespace per card returns dismissal to the exact tapped card,
/// including when the same title appears in several shelves.
struct MediaDetailLink<Label: View>: View {
    let media: MediaItem
    var onPresentationChanged: ((Bool) -> Void)? = nil
    var cardCornerRadius: CGFloat? = nil
    var includesCardMenu = false
    @ViewBuilder let label: () -> Label
    @Namespace private var transition
    @State private var presented = false
    @State private var watching = false
    @State private var menuVisible = false
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 18, *) {
            withCardMenu(styled(Button(action: openDetails) {
                label().contentShape(Rectangle()).matchedTransitionSource(id: media.key, in: transition)
            }))
            .accessibilityIdentifier("media-link-\(media.key)")
            .fullScreenCover(isPresented: $presented) {
                if reduceMotion {
                    destination
                } else {
                    destination.navigationTransition(.zoom(sourceID: media.key, in: transition))
                }
            }
            .fullScreenCover(isPresented: $watching) { watchDestination }
            .onChange(of: presented || watching || menuVisible) { _, visible in onPresentationChanged?(visible) }
        } else {
            withCardMenu(styled(Button(action: openDetails) { label().contentShape(Rectangle()) }))
                .accessibilityIdentifier("media-link-\(media.key)")
                .sheet(isPresented: $presented) {
                    destination.presentationDetents([.large])
                        .presentationDragIndicator(.visible).presentationCornerRadius(24)
                }
                .fullScreenCover(isPresented: $watching) { watchDestination }
                .onChange(of: presented || watching || menuVisible) { _, visible in onPresentationChanged?(visible) }
        }
    }

    @ViewBuilder private func styled<Content: View>(_ content: Content) -> some View {
        if let cardCornerRadius {
            content.buttonStyle(CardPressedButtonStyle(cornerRadius: cardCornerRadius,
                preservesContextMenuSource: includesCardMenu))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cardCornerRadius))
        } else { content.buttonStyle(HapticPlainButtonStyle()) }
    }

    private func openDetails() {
        // Card menus and their primary activation must share one native Button.
        // Non-card links retain the haptic behavior of their existing plain style.
        if cardCornerRadius != nil { AppHaptics.tap() }
        presented = true
    }

    @ViewBuilder private func withCardMenu<Content: View>(_ content: Content) -> some View {
        if includesCardMenu {
            content.contextMenu { cardMenu } preview: {
                // This preview has no transition source. The original tapped
                // card remains the sole native zoom anchor.
                PosterContent(media: media)
                    .frame(width: 208).padding(12)
                    .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onAppear { menuVisible = true }
                    .onDisappear { menuVisible = false }
            }
        } else { content }
    }

    @ViewBuilder private var cardMenu: some View {
        if includesCardMenu {
            Button("Details", systemImage: "info.circle") { presented = true }
            Button("Watch", systemImage: "play.fill") { watching = true }
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

    private var watchDestination: some View {
        let entry = library.history.first { $0.media.key == media.key }
        return MediaPlayerView(media: media, season: entry?.season ?? 1, episode: entry?.episode ?? 1)
    }

    private var destination: some View {
        NavigationStack { MediaDetailView(media: media) }
            .presentationBackground(AppTheme.canvas)
    }
}
