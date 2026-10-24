import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 69.0 / 255, blue: 79.0 / 255, alpha: 1)
        : UIColor(red: 190.0 / 255, green: 38.0 / 255, blue: 53.0 / 255, alpha: 1) })
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1)
        : UIColor(red: 0.965, green: 0.969, blue: 0.98, alpha: 1) })
    static let panel = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1) : .white })
    static let foreground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 245.0 / 255, alpha: 1) : UIColor(red: 28.0 / 255, green: 27.0 / 255, blue: 31.0 / 255, alpha: 1) })
    static let muted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 166.0 / 255, green: 166.0 / 255, blue: 174.0 / 255, alpha: 1)
        : UIColor(red: 87.0 / 255, green: 97.0 / 255, blue: 114.0 / 255, alpha: 1) })
    static let controlFill = foreground.opacity(0.06)
    static let border = Color.primary.opacity(0.10)
    static let rootTopTint = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 48.0 / 255, green: 39.0 / 255, blue: 53.0 / 255, alpha: 1)
        : UIColor(red: 231.0 / 255, green: 223.0 / 255, blue: 236.0 / 255, alpha: 1) })
}

/// The Android root backdrop fades from its plum tint to canvas over 420 dp.
/// A single stationary surface spans the root header, scrolling content and insets.
struct StreamifyRootBackdrop: View {
    var body: some View {
        AppTheme.canvas
            .overlay(alignment: .top) {
                LinearGradient(colors: [AppTheme.rootTopTint, AppTheme.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 420)
            }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func streamifyControlSurface(cornerRadius: CGFloat = 12) -> some View {
        background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(AppTheme.border, lineWidth: 1) }
    }
}

struct StreamifySelectLabel: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).foregroundStyle(AppTheme.muted) }
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
        }
        .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.foreground)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .streamifyControlSurface()
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RemoteArtwork: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { geometry in
            // The transparent surface owns layout and hit bounds. A fill image
            // can draw wider than this surface before clipping; it must never
            // contribute that larger frame to a parent button or accessibility.
            Color.clear
                .overlay {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: contentMode)
                        } else {
                            Rectangle().fill(AppTheme.panel)
                                .overlay { Image(systemName: "photo").font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary) }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
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
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(AppTheme.muted)
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
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: titleSize, weight: .bold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: labelSize, weight: .medium)).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12).frame(minHeight: 32)
                .foregroundStyle(selected ? AppTheme.canvas : AppTheme.muted)
                .background(selected ? AppTheme.foreground : AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.clear : AppTheme.border, lineWidth: 1) }
                .frame(minHeight: 44).contentShape(Rectangle())
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
            .foregroundStyle(AppTheme.canvas)
            .background(AppTheme.foreground.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .foregroundStyle(AppTheme.foreground)
            .background(AppTheme.foreground.opacity(configuration.isPressed ? 0.13 : 0.06), in: Capsule())
            .overlay { Capsule().strokeBorder(AppTheme.border, lineWidth: 1) }
    }
}

struct PosterCard: View {
    let media: MediaItem
    var rank: Int? = nil
    var roomy = false
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        MediaDetailLink(media: media) {
            PosterContent(media: media, rank: rank, roomy: roomy)
                .contentShape(Rectangle())
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

/// An explicit layout surface keeps portrait, landscape, missing and loading
/// artwork the same size. The source image never contributes its intrinsic size.
struct PosterArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var body: some View {
        Rectangle().fill(AppTheme.panel).aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { RemoteArtwork(url: url).allowsHitTesting(false) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct PosterContent: View {
    let media: MediaItem
    var rank: Int? = nil
    var roomy = false
    @ScaledMetric(relativeTo: .caption) private var roomyTitleSize: CGFloat = 13
    var body: some View {
            VStack(alignment: .leading, spacing: roomy ? 8 : 6) {
                PosterArtwork(url: media.posterURL, cornerRadius: roomy ? 12 : 8)
                    .overlay(alignment: .topTrailing) {
                        if media.rating > 0 {
                            Label(String(format: "%.1f", media.rating), systemImage: "star.fill")
                                .font(.caption2.bold()).padding(6)
                                .foregroundStyle(.white).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                                .padding(6)
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let rank {
                            Text(String(rank)).font(.system(size: 46, weight: .black, design: .rounded))
                                .foregroundStyle(.white).shadow(color: .black, radius: 4).padding(.leading, 8)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: roomy ? 12 : 8))
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(media.title) poster\(rank.map { ", number \($0)" } ?? "")")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("poster-artwork-\(media.key)")
                Text(media.title).font(roomy ? .system(size: roomyTitleSize, weight: .medium) : .caption.weight(.medium))
                    .lineLimit(roomy ? 2 : 1, reservesSpace: true).multilineTextAlignment(.leading)
                Text([media.year, media.kind.singular].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
    }
}

struct PosterRail: View {
    let title: String
    let items: [MediaItem]
    var ranked = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !title.isEmpty { SectionHeading(title: title).padding(.horizontal, 16) }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.key) { index, media in
                            PosterCard(media: media, rank: ranked ? index + 1 : nil).frame(width: 112)
                        }
                    }.padding(.horizontal, 16)
                }.scrollIndicators(.hidden)
            }
        }
    }
}

struct PosterGrid: View {
    let items: [MediaItem]
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 104
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth, maximum: 180), spacing: 12)], alignment: .leading, spacing: 24) {
            ForEach(items, id: \.key) { PosterCard(media: $0, roomy: true) }
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
