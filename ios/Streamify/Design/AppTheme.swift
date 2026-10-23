import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 1, green: 0.27, blue: 0.31)
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1)
        : UIColor(red: 0.965, green: 0.969, blue: 0.98, alpha: 1) })
    static let panel = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.086, green: 0.102, blue: 0.125, alpha: 1) : .white })
    static let muted = Color.secondary
    static let border = Color.primary.opacity(0.10)
}

struct RemoteArtwork: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    Rectangle().fill(AppTheme.panel)
                        .overlay { Image(systemName: "play.rectangle").font(.title).foregroundStyle(.tertiary) }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

struct StateMessage: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(AppTheme.accent)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity).padding(26)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 17).frame(minHeight: 44)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AppTheme.accent : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold())
            .padding(.horizontal, 20).frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
    }
}

struct PosterCard: View {
    let media: MediaItem
    var rank: Int? = nil
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationLink { MediaDetailView(media: media) } label: {
            VStack(alignment: .leading, spacing: 7) {
                RemoteArtwork(url: media.posterURL)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if media.rating > 0 {
                            Label(String(format: "%.1f", media.rating), systemImage: "star.fill")
                                .font(.caption2.bold()).padding(6)
                                .foregroundStyle(.white).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let rank {
                            Text(String(rank)).font(.system(size: 46, weight: .black, design: .rounded))
                                .foregroundStyle(.white).shadow(color: .black, radius: 4).padding(.leading, 8)
                                .accessibilityLabel("Number \(rank)")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                Text(media.title).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text([media.year, media.kind.singular].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(library.isSaved(media) ? "Remove from My list" : "Add to My list",
                   systemImage: library.isSaved(media) ? "checkmark" : "plus") { library.toggleSaved(media) }
            ShareLink(item: URL(string: media.kind == .anime
                ? "https://anilist.co/anime/\(media.id)" : "https://www.themoviedb.org/\(media.kind.rawValue)/\(media.id)")!)
        }
    }
}

struct PosterRail: View {
    let title: String
    let items: [MediaItem]
    var ranked = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if !title.isEmpty { SectionHeading(title: title).padding(.horizontal, 20) }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.key) { index, media in
                            PosterCard(media: media, rank: ranked ? index + 1 : nil).frame(width: 118)
                        }
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)
            }
        }
    }
}

struct PosterGrid: View {
    let items: [MediaItem]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 13)], alignment: .leading, spacing: 22) {
            ForEach(items, id: \.key) { PosterCard(media: $0) }
        }
    }
}

struct InlineError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(AppTheme.accent)
            Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry).font(.subheadline.bold()).frame(minHeight: 44)
        }
        .padding(16).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}
