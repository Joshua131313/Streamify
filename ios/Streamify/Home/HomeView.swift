import SwiftUI
import Combine
import UIKit

@MainActor
private final class HomeModel: ObservableObject {
    @Published var trending: [MediaItem] = []
    @Published var movies: [MediaItem] = []
    @Published var shows: [MediaItem] = []
    @Published var loading = false
    @Published var error: String?
    private var requestID = UUID()

    func load(token: String) async {
        let request = UUID(); requestID = request
        loading = true
        error = nil
        defer { if requestID == request { loading = false } }
        guard !token.isEmpty else { trending = []; movies = []; shows = []; return }
        let client = TMDBClient(token: token)
        do {
            async let trendingPage = client.catalog(path: "trending/all/day")
            async let moviePage = client.catalog(path: "movie/top_rated", kind: .movie)
            async let showPage = client.catalog(path: "tv/popular", kind: .tv)
            let pages = try await (trendingPage, moviePage, showPage)
            try Task.checkCancellation()
            guard requestID == request else { return }
            trending = pages.0.items
            movies = pages.1.items
            shows = pages.2.items
        } catch is CancellationError { }
        catch { if requestID == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct HomeView: View {
    let openSettings: () -> Void
    let openSports: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model = HomeModel()
    @State private var retry = 0
    @State private var carouselVisible = true
    @State private var interacting = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        categoryLink("Shows", kind: .tv)
                        categoryLink("Movies", kind: .movie)
                        categoryLink("Anime", kind: .anime)
                        Pill(title: "Live sports", selected: false, action: openSports)
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)

                if settings.tmdbToken.isEmpty {
                    StateMessage(symbol: "sparkles.tv", title: "Your next favorite awaits.",
                                 message: "Connect your TMDB key to explore movies and shows. Anime and live sports are ready to browse.",
                                 actionTitle: "Set up catalog", action: openSettings).padding(.horizontal, 20)
                }
                if model.loading && model.trending.isEmpty {
                    ProgressView("Finding something great…").frame(maxWidth: .infinity).padding(50)
                }
                if let error = model.error {
                    InlineError(message: error) { retry += 1 }.padding(.horizontal, 20)
                }
                if !model.trending.isEmpty {
                    FeaturedCarousel(items: Array(model.trending.prefix(5)), visible: carouselVisible && !interacting)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: HeroPositionKey.self, value: geometry.frame(in: .named("home-scroll")))
                            }
                        }
                }
                if !library.history.isEmpty { ContinueWatchingRail() }
                Button(action: openSports) {
                    HStack(spacing: 16) {
                        Image(systemName: "basketball.fill").font(.title).foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The game is on.").font(.headline)
                            Text("Live scores, schedules & streams").font(.caption).foregroundStyle(AppTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.headline)
                    }.padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).padding(.horizontal, 20)

                PosterRail(title: "TOP 10 Today", items: Array(model.trending.prefix(10)), ranked: true)
                PosterRail(title: "Popular shows", items: model.shows)
                PosterRail(title: "Top rated movies", items: model.movies)
                if !settings.tmdbToken.isEmpty {
                    DiscoveryRail(title: "For you", mode: .forYou)
                    DiscoveryRail(title: "Trending Today", mode: .trending)
                    DiscoveryRail(title: "Only on", mode: .provider)
                    DiscoveryRail(title: "Explore genres", mode: .genre)
                }
                collections
                Text("Film and series data by TMDB · Anime by AniList")
                    .font(.caption2).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
            }.padding(.top, 16).padding(.bottom, 24)
        }
        .coordinateSpace(name: "home-scroll")
        .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { _ in interacting = true }.onEnded { _ in interacting = false })
        .onPreferenceChange(HeroPositionKey.self) { frame in
            carouselVisible = frame.maxY > frame.height * 0.7 && frame.minY < 250
        }
        .background {
            LinearGradient(colors: [Color.purple.opacity(0.12), AppTheme.canvas], startPoint: .top, endPoint: .center).ignoresSafeArea()
        }
        .task(id: settings.tmdbToken + String(retry)) { await model.load(token: settings.tmdbToken) }
        .refreshable { await model.load(token: settings.tmdbToken) }
    }

    private func categoryLink(_ title: String, kind: MediaKind) -> some View {
        NavigationLink { CategoryView(kind: kind) } label: {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
                .background(Color.primary.opacity(0.09), in: Capsule())
        }.buttonStyle(.plain)
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: "Collections")
                NavigationLink { CollectionsView() } label: {
                    Text("Explore all").font(.caption.weight(.semibold)).fixedSize()
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
            }.padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(FilmCollection.bundled.filter(\.featured)) { collection in
                        NavigationLink { CollectionDetailView(collection: collection) } label: {
                            Image(collection.assetName).resizable().scaledToFill().frame(width: 220, height: 125)
                                .overlay(alignment: .bottomLeading) {
                                    Text(collection.name).font(.headline).foregroundStyle(.white).padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                }.clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
    }
}

private struct HeroPositionKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct FeaturedCarousel: View {
    let items: [MediaItem]
    var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    @State private var index = 0
    @State private var paused = false
    @State private var voiceOver = UIAccessibility.isVoiceOverRunning
    @State private var player: MediaItem?

    private var running: Bool { visible && !paused && !reduceMotion && !voiceOver && scenePhase == .active && player == nil }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.key) { offset, media in
                    hero(media).padding(.horizontal, 20).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(0.82, contentMode: .fit).frame(maxHeight: 620)
            HStack(spacing: 3) {
                ForEach(items.indices, id: \.self) { offset in
                    Button { index = offset } label: {
                        Capsule().fill(index == offset ? Color.primary : Color.primary.opacity(0.25))
                            .frame(width: index == offset ? 25 : 6, height: 4).frame(width: 38, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Show \(items[offset].title)")
                        .accessibilityAddTraits(index == offset ? .isSelected : [])
                }
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill").font(.caption.bold()).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(paused ? "Resume carousel" : "Pause carousel")
            }.foregroundStyle(AppTheme.muted)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOver = UIAccessibility.isVoiceOverRunning
        }
        .task(id: "\(index)-\(running)") {
            guard running && items.count > 1 else { return }
            do {
                try await Task.sleep(for: .seconds(6.5))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.45)) { index = (index + 1) % items.count }
            } catch { }
        }
        .fullScreenCover(item: $player) { media in
            let entry = library.history.first { $0.media.key == media.key }
            MediaPlayerView(media: media, season: entry?.season ?? 1, episode: entry?.episode ?? 1)
        }
    }

    private func hero(_ media: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteArtwork(url: media.posterURL ?? media.backdropURL)
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.28), location: 0.58),
                                   .init(color: Color(red: 0.10, green: 0.08, blue: 0.12), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                Text(media.title).font(.title.bold()).lineLimit(2)
                Text([media.year, media.kind.singular, String(format: "★ %.1f", media.rating)].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 10) {
                    Button { player = media } label: {
                        Label(media.kind == .movie ? "Play movie" : "Play show", systemImage: "play.fill")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(minHeight: 48)
                            .foregroundStyle(.black).background(.white, in: Capsule())
                    }
                    Button { library.toggleSaved(media) } label: {
                        Label("My list", systemImage: library.isSaved(media) ? "checkmark" : "plus")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(minHeight: 48)
                            .background(.white.opacity(0.18), in: Capsule())
                    }.accessibilityLabel(library.isSaved(media) ? "Remove \(media.title) from My list" : "Save \(media.title)")
                }.buttonStyle(.plain)
            }.padding(18).foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            NavigationLink { MediaDetailView(media: media) } label: {
                Image(systemName: "info.circle.fill").font(.title3).foregroundStyle(.white).frame(width: 48, height: 48)
            }.accessibilityLabel("Details for \(media.title)")
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 1) }
    }
}

private struct ContinueWatchingRail: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selected: WatchEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Continue watching").padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(library.history.filter { !$0.completed }.prefix(12))) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { selected = entry } label: {
                                RemoteArtwork(url: entry.media.backdropURL ?? entry.media.posterURL)
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .overlay { Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white).shadow(radius: 6) }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("Resume \(entry.media.title)")
                            Text(entry.media.title).font(.caption.bold()).lineLimit(1)
                            if entry.media.kind != .movie {
                                Text("Season \(entry.season) · Episode \(entry.episode)").font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                        }.frame(width: 210)
                            .contextMenu {
                                NavigationLink("Details") { MediaDetailView(media: entry.media) }
                                Button("Remove from history", role: .destructive) { library.removeHistory(entry) }
                            }
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $selected) { MediaPlayerView(media: $0.media, season: $0.season, episode: $0.episode) }
    }
}

private enum DiscoveryMode { case forYou, trending, provider, genre }

private struct DiscoveryRail: View {
    let title: String
    let mode: DiscoveryMode
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @State private var kind: MediaKind = .movie
    @State private var provider = 8
    @State private var genre = 28
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var requestID = UUID()
    private let providers = [(8, "Netflix"), (9, "Prime"), (337, "Disney+"), (350, "Apple TV"), (15, "Hulu"), (531, "Paramount+")]
    private let genres = [(28, "Action"), (12, "Adventure"), (35, "Comedy"), (18, "Drama"), (14, "Fantasy"), (27, "Horror"), (878, "Sci-Fi")]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { SectionHeading(title: title); controls }
                VStack(alignment: .leading, spacing: 10) { SectionHeading(title: title); controls }
            }.padding(.horizontal, 20)
            if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(24) }
            if let error { InlineError(message: error) { retry += 1 }.padding(.horizontal, 20) }
            PosterRail(title: "", items: items)
            if items.isEmpty && !loading && error == nil {
                Text("No titles found for these filters.").font(.subheadline).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
            }
        }
        .task(id: "\(settings.tmdbToken)-\(kind.rawValue)-\(provider)-\(genre)-\(library.favoriteGenres)-\(retry)") { await load() }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Picker("Media type", selection: $kind) { Text("Movies").tag(MediaKind.movie); Text("Shows").tag(MediaKind.tv) }.fixedSize()
            if mode == .provider {
                Picker("Provider", selection: $provider) { ForEach(providers, id: \.0) { Text($0.1).tag($0.0) } }.fixedSize()
            }
            if mode == .genre {
                Picker("Genre", selection: $genre) {
                    ForEach(kind == .movie ? genres : [(10759, "Action"), (35, "Comedy"), (18, "Drama"), (10765, "Sci-Fi")], id: \.0) { Text($0.1).tag($0.0) }
                }.fixedSize()
            }
        }.pickerStyle(.menu).font(.caption).tint(AppTheme.muted)
            .onChange(of: kind) { _, value in if mode == .genre { genre = value == .movie ? 28 : 10759 } }
    }

    private func load() async {
        let request = UUID(); requestID = request
        loading = true; error = nil
        defer { if requestID == request { loading = false } }
        do {
            var params: [String: String] = [:]
            var path = "discover/\(kind.rawValue)"
            if mode == .trending { path = "trending/\(kind.rawValue)/day" }
            if mode == .provider { params = ["with_watch_providers": String(provider), "watch_region": "US"] }
            if mode == .genre { params["with_genres"] = String(genre) }
            if mode == .forYou {
                let available: Set<Int> = kind == .movie ? [28,12,35,18,14,27,878,53,16,10751,10749,9648,80] : [10759,35,18,10765,16,10751,9648,80]
                let selected = library.favoriteGenres.filter { available.contains($0) }
                if selected.isEmpty { path = "trending/\(kind.rawValue)/week" }
                else { params["with_genres"] = selected.prefix(3).map(String.init).joined(separator: "|") }
            }
            let result = try await settings.client.catalog(path: path, kind: kind, parameters: params)
            try Task.checkCancellation()
            guard requestID == request else { return }
            items = result.items
        } catch is CancellationError { }
        catch { if requestID == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
