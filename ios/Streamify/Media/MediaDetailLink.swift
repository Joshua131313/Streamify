import SwiftUI

/// A distinct namespace per card returns dismissal to the exact tapped card,
/// including when the same title appears in several shelves.
struct MediaDetailLink<Label: View>: View {
    let media: MediaItem
    var onPresentationChanged: ((Bool) -> Void)? = nil
    @ViewBuilder let label: () -> Label
    @Namespace private var transition
    @State private var presented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 18, *) {
            Button { presented = true } label: {
                label().contentShape(Rectangle()).matchedTransitionSource(id: media.key, in: transition)
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityIdentifier("media-link-\(media.key)")
            .fullScreenCover(isPresented: $presented) {
                if reduceMotion {
                    destination
                } else {
                    destination.navigationTransition(.zoom(sourceID: media.key, in: transition))
                }
            }
            .onChange(of: presented) { _, visible in onPresentationChanged?(visible) }
        } else {
            Button { presented = true } label: { label().contentShape(Rectangle()) }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityIdentifier("media-link-\(media.key)")
                .sheet(isPresented: $presented) {
                    destination.presentationDetents([.large])
                        .presentationDragIndicator(.visible).presentationCornerRadius(24)
                }
                .onChange(of: presented) { _, visible in onPresentationChanged?(visible) }
        }
    }

    private var destination: some View {
        NavigationStack { MediaDetailView(media: media) }
            .presentationBackground(AppTheme.canvas)
    }
}
