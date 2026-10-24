import SwiftUI

/// A compact resume row shows only progress actually recorded by the player.
struct WatchHistoryCard: View {
    let entry: WatchEntry
    let resume: () -> Void
    @EnvironmentObject private var library: LibraryStore

    private var subtitle: String {
        let episode: String
        switch entry.media.kind {
        case .movie: episode = ""
        case .tv: episode = "S\(entry.season) · E\(entry.episode)"
        case .anime: episode = "Episode \(entry.episode)"
        }
        let status = entry.durationSeconds > 0
            ? (entry.completed ? "Watched" : "\(Int(ceil(max(0, entry.durationSeconds - entry.positionSeconds) / 60))) min left")
            : "Recently opened"
        return [episode, status].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                Button(action: resume) {
                    Color.clear.frame(width: 128, height: 72)
                        .overlay { RemoteArtwork(url: entry.media.backdropURL ?? entry.media.posterURL) }
                        .overlay {
                            Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white).offset(x: 2)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5), in: Circle())
                                .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
                                .accessibilityHidden(true)
                        }
                        .clipped().contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume \(entry.media.title)")
                .accessibilityIdentifier("history-resume-\(entry.id)")

                if entry.durationSeconds > 0 {
                    ProgressView(value: entry.progress)
                        .progressViewStyle(.linear).tint(AppTheme.accent)
                        .frame(height: 3).background(.white.opacity(0.25), in: Capsule()).clipShape(Capsule())
                        .accessibilityLabel("Watch progress for \(entry.media.title)")
                        .accessibilityValue("\(Int(entry.progress * 100)) percent")
                        .accessibilityIdentifier("history-progress-\(entry.id)")
                        .allowsHitTesting(false)
                        .padding(.horizontal, 8).padding(.bottom, 6)
                }
            }
            .frame(width: 128, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)

            VStack(alignment: .leading, spacing: 6) {
                MediaDetailLink(media: entry.media) {
                    Text(entry.media.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground).lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                    .accessibilityIdentifier("history-status-\(entry.id)")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Remove from history", systemImage: "trash", role: .destructive) { library.removeHistory(entry) }
                Button(library.isSaved(entry.media) ? "Remove from My list" : "Add to My list", systemImage: "bookmark") { library.toggleSaved(entry.media) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.muted).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Actions for \(entry.media.title)")
        }
        .padding(12).background(AppTheme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-card-\(entry.id)")
    }
}
