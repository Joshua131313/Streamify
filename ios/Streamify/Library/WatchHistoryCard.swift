import SwiftUI

/// A landscape resume card shows only progress actually recorded by the player.
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
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Button(action: resume) {
                    Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay { RemoteArtwork(url: entry.media.backdropURL ?? entry.media.posterURL) }
                        .overlay {
                            Image(systemName: "play.fill").font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white).offset(x: 2)
                                .frame(width: 52, height: 52)
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
                        .frame(height: 4).background(.white.opacity(0.2))
                        .accessibilityLabel("Watch progress for \(entry.media.title)")
                        .accessibilityValue("\(Int(entry.progress * 100)) percent")
                        .accessibilityIdentifier("history-progress-\(entry.id)")
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    MediaDetailLink(media: entry.media) {
                        Text(entry.media.title).font(.headline)
                            .foregroundStyle(AppTheme.foreground).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.muted)
                        .accessibilityIdentifier("history-status-\(entry.id)")
                    Text(entry.watchedAt, style: .date).font(.caption2).foregroundStyle(AppTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Remove from history", systemImage: "trash", role: .destructive) { library.removeHistory(entry) }
                    Button(library.isSaved(entry.media) ? "Remove from My list" : "Add to My list", systemImage: "bookmark") { library.toggleSaved(entry.media) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 19, weight: .medium))
                        .foregroundStyle(AppTheme.muted).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Actions for \(entry.media.title)")
            }.padding(.leading, 14).padding(.trailing, 5).padding(.vertical, 14)
        }
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-card-\(entry.id)")
    }
}
