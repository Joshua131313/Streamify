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
    private var loadedToken: String?
    private var loadedAt: Date?

    func load(client: TMDBClient, forceReload: Bool = false) async {
        if loadedToken != client.token {
            trending = []; movies = []; shows = []; loadedAt = nil; loadedToken = client.token
        }
        if !forceReload, error == nil, let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        let request = UUID(); requestID = request
        loading = true
        error = nil
        defer { if requestID == request { loading = false } }
        guard !client.token.isEmpty else { trending = []; movies = []; shows = []; return }
        do {
            let client = client.reloading(forceReload)
            async let trendingPage = client.catalog(path: "trending/all/day")
            async let moviePage = client.catalog(path: "movie/top_rated", kind: .movie)
            async let showPage = client.catalog(path: "tv/popular", kind: .tv)
            let pages = try await (trendingPage, moviePage, showPage)
            try Task.checkCancellation()
            guard requestID == request else { return }
            trending = pages.0.items
            movies = pages.1.items
            shows = pages.2.items
            loadedAt = Date()
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
    @State private var handledRetry = 0
    @State private var carouselFrame: CGRect = .null
    @State private var viewportFrame: CGRect = .null
    @State private var scrollMoving = false
    @GestureState private var interacting = false

    private var carouselVisible: Bool {
        guard !carouselFrame.isNull, !viewportFrame.isNull, carouselFrame.height > 0, viewportFrame.height > 0 else { return true }
        let intersection = carouselFrame.intersection(viewportFrame)
        return !intersection.isNull && intersection.height > carouselFrame.height * 0.7
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        categoryLink("Shows", kind: .tv)
                        categoryLink("Movies", kind: .movie)
                        categoryLink("Anime", kind: .anime)
                        Button(action: openSports) { shortcutLabel("Live sports") }.buttonStyle(HapticPlainButtonStyle())
                    }.padding(.horizontal, 16)
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
                    FeaturedCarousel(items: Array(model.trending.prefix(5)), visible: carouselVisible && !interacting && !scrollMoving)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: HeroPositionKey.self, value: geometry.frame(in: .global))
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                }
                if library.history.contains(where: { !$0.completed }) { ContinueWatchingRail() }
                Button(action: openSports) {
                    HStack(spacing: 14) {
                        Image(systemName: "basketball.fill").font(.title2).foregroundStyle(AppTheme.muted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The game is on.").font(.headline)
                            Text("Live scores, schedules & streams").font(.caption).foregroundStyle(AppTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.headline)
                    }.padding(18).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(HapticCardButtonStyle(cornerRadius: 16)).padding(.horizontal, 20)

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
                    .font(.caption2).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
            }.padding(.top, 4).padding(.bottom, 110)
        }
        .accessibilityIdentifier("home-catalog")
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: HomeViewportKey.self, value: geometry.frame(in: .global))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        // GestureState resets after cancellation as well as a completed drag.
        // A competing ScrollView/TabView recognizer must not leave autoplay paused.
        .simultaneousGesture(DragGesture(minimumDistance: 5).updating($interacting) { _, value, _ in value = true })
        .onPreferenceChange(HeroPositionKey.self) { frame in
            if !frame.isNull && !frame.isEmpty { carouselFrame = frame }
        }
        .onPreferenceChange(HomeViewportKey.self) { frame in
            if !frame.isNull && !frame.isEmpty { viewportFrame = frame }
        }
        .task(id: carouselFrame.minY) {
            guard !carouselFrame.isNull else { return }
            scrollMoving = true
            do {
                try await Task.sleep(for: .milliseconds(180))
                try Task.checkCancellation()
                scrollMoving = false
            } catch { }
        }
        .task(id: settings.tmdbToken + String(retry)) {
            let reload = retry != handledRetry; handledRetry = retry
            await model.load(client: settings.client, forceReload: reload)
        }
        .refreshable { await model.load(client: settings.client, forceReload: true) }
    }

    private func categoryLink(_ title: String, kind: MediaKind) -> some View {
        NavigationLink { CategoryView(kind: kind) } label: {
            shortcutLabel(title)
        }.buttonStyle(HapticPlainButtonStyle())
    }

    private func shortcutLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 17).padding(.vertical, 10)
            .foregroundStyle(AppTheme.foreground)
            .background(AppTheme.foreground.opacity(0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(0.12), lineWidth: 0.5) }
            .frame(minHeight: 48)
            .contentShape(Capsule())
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "Collections")
                NavigationLink { CollectionsView() } label: {
                    HStack(spacing: 4) {
                        Text("Explore all").font(.caption2.weight(.medium)).fixedSize()
                        Image(systemName: "arrow.right").font(.caption2)
                    }.foregroundStyle(AppTheme.muted).frame(minHeight: 44)
                }.buttonStyle(HapticPlainButtonStyle())
            }.padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(FilmCollection.bundled.filter(\.featured)) { collection in
                        NavigationLink { CollectionDetailView(collection: collection) } label: {
                            Rectangle().fill(AppTheme.panel).frame(width: 260, height: 180)
                                .overlay {
                                    Image(collection.assetName).resizable().scaledToFill()
                                        .frame(width: 260, height: 180).clipped().allowsHitTesting(false).accessibilityHidden(true)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text(collection.name).font(.title3.bold()).foregroundStyle(.white).padding(20)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                                }.clipShape(RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Explore collection \(collection.name)")
                        }.buttonStyle(HapticCardButtonStyle(cornerRadius: 16))
                    }
                }.padding(.horizontal, 16)
            }.scrollIndicators(.hidden)
        }
    }
}

private struct HeroPositionKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct HomeViewportKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct FeaturedCarousel: View {
    let items: [MediaItem]
    var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var library: LibraryStore
    @ScaledMetric(relativeTo: .title2) private var heroTitleSize: CGFloat = 24
    @State private var index = 0
    @State private var paused = false
    @State private var voiceOver = UIAccessibility.isVoiceOverRunning
    @State private var player: MediaItem?
    @State private var detailsPresented = false
    @State private var appeared = false
    @GestureState private var dragging = false
    @State private var cycleStartedAt: Date?
    @State private var settledAfter = Date.distantPast
    @State private var cycleRevision = 0
    private let slideDuration: TimeInterval = 6.5
    private let transitionDuration: TimeInterval = 0.55

    private var running: Bool {
        appeared && visible && !paused && !dragging && !reduceMotion && !voiceOver &&
        scenePhase == .active && player == nil && !detailsPresented && items.count > 1
    }
    private var cycleKey: String { "\(index)-\(running)-\(cycleRevision)-\(items.map(\.key).joined(separator: "|"))" }

    var body: some View {
        VStack(spacing: 4) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.key) { offset, media in
                    hero(media).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(horizontalSizeClass == .regular ? 16.0 / 9.0 : 0.82, contentMode: .fit)
            .frame(maxHeight: horizontalSizeClass == .regular ? 320 : 620)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("hero-carousel")
            .simultaneousGesture(DragGesture(minimumDistance: 5)
                .updating($dragging) { _, value, _ in value = true })
            if items.count > 1 { indicators }
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false; cycleStartedAt = nil }
        .onChange(of: index) { _, _ in resetCycle(after: transitionDuration) }
        .onChange(of: dragging) { wasDragging, isDragging in
            if wasDragging && !isDragging { resetCycle(after: transitionDuration) }
        }
        .onChange(of: items.map(\.key)) { _, keys in
            index = min(index, max(0, keys.count - 1))
            resetCycle()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOver = UIAccessibility.isVoiceOverRunning
        }
        .task(id: cycleKey) {
            cycleStartedAt = nil
            guard running else { return }
            do {
                // A swipe or a programmatic page change finishes before the next timed cycle begins.
                let settling = settledAfter.timeIntervalSinceNow
                if settling > 0 { try await Task.sleep(for: .seconds(settling)) }
                try Task.checkCancellation()
                guard running else { return }
                cycleStartedAt = Date()
                try await Task.sleep(for: .seconds(slideDuration))
                try Task.checkCancellation()
                guard running else { return }
                withAnimation(.easeInOut(duration: transitionDuration)) { index = (index + 1) % items.count }
            } catch { }
        }
        .fullScreenCover(item: $player) { media in
            let entry = library.history.first { $0.media.key == media.key }
            MediaPlayerView(media: media, season: entry?.season ?? 1, episode: entry?.episode ?? 1)
        }
    }

    private var indicators: some View {
        // Only this small row redraws on the display timeline; the artwork and feed remain unchanged.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running)) { context in
            let progress = cycleProgress(at: context.date)
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { offset in
                    let selected = offset == index
                    Button { selectSlide(offset) } label: {
                        Capsule().fill(AppTheme.muted.opacity(0.3))
                            .overlay(alignment: .leading) {
                                if selected {
                                    GeometryReader { geometry in
                                        AppTheme.foreground.frame(width: geometry.size.width * (running ? max(0.12, progress) : 1))
                                    }
                                }
                            }
                            .frame(width: selected ? 28 : 6, height: 4)
                            .clipShape(Capsule())
                            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.9), value: selected)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Show \(items[offset].title)")
                    .accessibilityValue(selected ? (running ? "\(Int(progress * 100)) percent, current slide" : "Current slide, automatic playback paused") : "Not selected")
                    .accessibilityIdentifier(selected ? "hero-main-progress" : "hero-slide-indicator-\(offset)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                if !voiceOver {
                    Button { paused.toggle() } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .font(.body).frame(width: 48, height: 48)
                    }
                    .buttonStyle(HapticPlainButtonStyle()).accessibilityLabel(paused ? "Resume carousel" : "Pause carousel")
                    .accessibilityValue(paused ? "Paused" : running ? "Playing" : "Automatic playback paused")
                    .accessibilityIdentifier("hero-carousel-pause")
                }
            }.foregroundStyle(AppTheme.muted)
        }
    }

    private func cycleProgress(at date: Date) -> Double {
        guard let cycleStartedAt, running else { return 0 }
        return min(1, max(0, date.timeIntervalSince(cycleStartedAt) / slideDuration))
    }

    private func resetCycle(after delay: TimeInterval = 0) {
        cycleStartedAt = nil
        settledAfter = Date().addingTimeInterval(reduceMotion ? 0 : delay)
        cycleRevision += 1
    }

    private func selectSlide(_ offset: Int) {
        guard items.indices.contains(offset) else { return }
        resetCycle(after: transitionDuration)
        if reduceMotion { index = offset }
        else { withAnimation(.easeInOut(duration: transitionDuration)) { index = offset } }
    }

    private func hero(_ media: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            MediaDetailLink(media: media, onPresentationChanged: { detailsPresented = $0 }, cardCornerRadius: 16, includesCardMenu: true) {
                RemoteArtwork(url: horizontalSizeClass == .regular ? media.heroBackdropURL : media.heroPosterURL)
                    .overlay {
                        LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                               .init(color: Color(red: 27 / 255, green: 23 / 255, blue: 32 / 255).opacity(0.7), location: 0.8),
                                               .init(color: Color(red: 27 / 255, green: 23 / 255, blue: 32 / 255), location: 1)], startPoint: .top, endPoint: .bottom)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Details for \(media.title)")
            VStack(alignment: .leading, spacing: 14) {
                Text(media.title).font(.system(size: heroTitleSize, weight: .bold)).lineLimit(2).allowsHitTesting(false)
                Text([media.year, media.kind.singular, String(format: "★ %.1f", media.rating)].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.caption.weight(.medium)).foregroundStyle(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255))
                    .allowsHitTesting(false)
                HStack(spacing: 12) {
                    Button { player = media } label: {
                        Label("Watch", systemImage: "play.fill")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(minHeight: 44)
                            .foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                    }.accessibilityLabel("Watch \(media.title)")
                    Button { library.toggleSaved(media) } label: {
                        Label(library.isSaved(media) ? "Added" : "My list", systemImage: library.isSaved(media) ? "checkmark" : "plus")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 44)
                            .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                            .overlay { RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius).strokeBorder(.white.opacity(0.15), lineWidth: 0.7) }
                    }.accessibilityLabel(library.isSaved(media) ? "Remove \(media.title) from My list" : "Save \(media.title)")
                }.buttonStyle(HapticPlainButtonStyle()).padding(.top, 6)
            }.padding(14).foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "info.circle").font(.title3).foregroundStyle(.white).frame(width: 48, height: 48)
                .padding(6).allowsHitTesting(false).accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16), lineWidth: 1) }
    }
}

private struct ContinueWatchingRail: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selected: WatchEntry?
    @State private var selectedDetails: MediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Continue watching").padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(library.history.filter { !$0.completed }.prefix(12))) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { selected = entry } label: {
                                WatchHistoryArtwork(media: entry.media)
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .overlay {
                                        Image(systemName: "play.fill").font(.body)
                                            .frame(width: 38, height: 38).foregroundStyle(.white)
                                            .background(.black.opacity(0.65), in: Circle())
                                            .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if entry.durationSeconds > 0 {
                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    Color.white.opacity(0.3)
                                                    AppTheme.accent.frame(width: geometry.size.width * entry.progress)
                                                }
                                            }.frame(height: 4)
                                                .accessibilityLabel("\(Int(entry.progress * 100)) percent watched")
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(HapticCardButtonStyle(cornerRadius: 12)).accessibilityLabel("Resume \(entry.media.title)")
                            Text(entry.media.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(watchSubtitle(entry)).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                        }.frame(width: 184)
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
                            .contextMenu {
                                Button("Resume", systemImage: "play.fill") { selected = entry }
                                Button("Details", systemImage: "info.circle") { selectedDetails = entry.media }
                                Button("Remove from history", role: .destructive) { library.removeHistory(entry) }
                            }
                    }
                }.padding(.horizontal, 16)
            }.scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $selected) { MediaPlayerView(media: $0.media, season: $0.season, episode: $0.episode) }
        .fullScreenCover(item: $selectedDetails) { media in
            NavigationStack { MediaDetailView(media: media) }.presentationBackground(AppTheme.canvas)
        }
    }

    private func watchSubtitle(_ entry: WatchEntry) -> String {
        let episode = entry.media.kind == .tv ? "S\(entry.season) · E\(entry.episode) · " : ""
        guard entry.durationSeconds > 0 else { return episode + "Recently watched" }
        let minutes = Int(ceil(max(0, entry.durationSeconds - entry.positionSeconds) / 60))
        return episode + "\(minutes) min left"
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
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    SectionHeading(title: title).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    controls.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeading(title: title)
                    ScrollView(.horizontal) { controls }.scrollIndicators(.hidden)
                }
            }.padding(.horizontal, 16)
            if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(24) }
            if let error { InlineError(message: error) { retry += 1 }.padding(.horizontal, 16) }
            MediaExploreRail(identifier: String(describing: mode), items: items)
            if items.isEmpty && !loading && error == nil {
                Text("No titles found for these filters.").font(.subheadline).foregroundStyle(AppTheme.muted).padding(.horizontal, 16)
            }
        }
        .task(id: "\(settings.tmdbToken)-\(kind.rawValue)-\(provider)-\(genre)-\(library.favoriteGenres)-\(retry)") { await load() }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Media type", selection: $kind) { Text("Movies").tag(MediaKind.movie); Text("Series").tag(MediaKind.tv) }
            } label: { compactChoiceLabel(kind == .movie ? "Movies" : "Series") }
                .accessibilityLabel("Media type, \(kind == .movie ? "Movies" : "Series")")
                .accessibilityIdentifier("home-choice-media-\(mode)")
            if mode == .provider {
                Menu {
                    Picker("Provider", selection: $provider) { ForEach(providers, id: \.0) { Text($0.1).tag($0.0) } }
                } label: { compactChoiceLabel(providers.first { $0.0 == provider }?.1 ?? "Provider") }
                    .accessibilityLabel("Provider, \(providers.first { $0.0 == provider }?.1 ?? "Choose provider")")
                    .accessibilityIdentifier("home-choice-provider")
            }
            if mode == .genre {
                Menu {
                    Picker("Genre", selection: $genre) {
                        ForEach(availableGenres, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } label: { compactChoiceLabel(availableGenres.first { $0.0 == genre }?.1 ?? "Genre") }
                    .accessibilityLabel("Genre, \(availableGenres.first { $0.0 == genre }?.1 ?? "Choose genre")")
                    .accessibilityIdentifier("home-choice-genre")
            }
        }.buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.foreground)
            .onChange(of: kind) { _, value in if mode == .genre { genre = value == .movie ? 28 : 10759 } }
    }

    private var availableGenres: [(Int, String)] {
        kind == .movie ? genres : [(10759, "Action"), (35, "Comedy"), (18, "Drama"), (10765, "Sci-Fi")]
    }

    private func compactChoiceLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(AppTheme.foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
        .frame(minHeight: 48)
        .contentShape(Rectangle())
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
