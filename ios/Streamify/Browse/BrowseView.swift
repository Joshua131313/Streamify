import SwiftUI
import Combine

@MainActor
private final class BrowseModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var genres: [CatalogGenre] = []
    @Published var loading = false
    @Published var error: String?
    @Published var page = 0
    @Published var totalPages = 1
    private var generation = UUID()

    func reset() { generation = UUID(); items = []; page = 0; totalPages = 1; error = nil; loading = false }

    func load(client: TMDBClient, kind: MediaKind?, query: String, genre: Int, animeGenre: String, provider: Int, topRated: Bool, first: Bool) async {
        if first { reset() }
        guard !loading, page < totalPages else { return }
        let request = generation
        loading = true; error = nil
        defer { if request == generation { loading = false } }
        do {
            let resolved = kind ?? .movie
            var params: [String: String] = [:]
            var path: String
            if !query.isEmpty { path = "search/\(kind?.rawValue ?? "multi")" }
            else if genre > 0 || provider > 0 { path = "discover/\(resolved.rawValue)" }
            else if kind == nil { path = "trending/all/week" }
            else { path = "\(resolved.rawValue)/\(topRated ? "top_rated" : "popular")" }
            if resolved == .anime {
                if !animeGenre.isEmpty { params["genre"] = animeGenre }
            } else {
                if genre > 0 { params["with_genres"] = String(genre) }
                if provider > 0 { params["with_watch_providers"] = String(provider); params["watch_region"] = "US" }
                if topRated && path.hasPrefix("discover") { params["sort_by"] = "vote_average.desc"; params["vote_count.gte"] = "200" }
            }
            let response = try await client.catalog(path: path, kind: kind, page: page + 1, query: query, parameters: params)
            try Task.checkCancellation()
            guard request == generation else { return }
            var seen = Set(items.map(\.key))
            items.append(contentsOf: response.items.filter { seen.insert($0.key).inserted })
            page = response.page; totalPages = response.totalPages
        } catch is CancellationError { }
        catch { if request == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

@MainActor
struct BrowseView: View {
    var initialKind: MediaKind? = nil
    var category = false
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .caption) private var chipLabelSize: CGFloat = 13
    @StateObject private var model = BrowseModel()
    @State private var kind: MediaKind?
    @State private var query = ""
    @State private var genre = 0
    @State private var animeGenre = ""
    @State private var provider = 0
    @State private var topRated = false
    @State private var revision = 0
    @FocusState private var focused: Bool
    private let providers = [(0, "All providers"), (8, "Netflix"), (9, "Prime Video"), (337, "Disney+"), (350, "Apple TV"), (15, "Hulu"), (531, "Paramount+")]
    private let animeGenres = ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Romance", "Sci-Fi", "Sports", "Thriller"]

    init(initialKind: MediaKind? = nil, category: Bool = false) {
        self.initialKind = initialKind; self.category = category
        _kind = State(initialValue: initialKind)
    }

    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pageGutter: CGFloat { horizontalSizeClass == .regular ? 20 : 16 }
    private var requestKey: String { "\(kind?.rawValue ?? "all")-\(cleanQuery)-\(genre)-\(animeGenre)-\(provider)-\(topRated)-\(revision)-\(settings.tmdbToken)" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !category {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                        TextField(kind == .anime ? "Search anime" : "Search movies & series", text: $query)
                            .accessibilityIdentifier("browse-search")
                            .font(.subheadline)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($focused)
                            .onSubmit { library.rememberSearch(cleanQuery); focused = false }
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark").foregroundStyle(AppTheme.muted).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Clear search")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 56)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, pageGutter)
                    VStack(alignment: .leading, spacing: 12) {
                        if cleanQuery.isEmpty { SectionHeading(title: "Find your next favorite").padding(.horizontal, pageGutter) }
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                Pill(title: "All", selected: kind == nil) { kind = nil }
                                ForEach(MediaKind.allCases) { value in
                                    Pill(title: value == .tv ? "Series" : value.title, selected: kind == value) { kind = value }
                                }
                                NavigationLink { CollectionsView() } label: {
                                    Text("Collections").font(.system(size: chipLabelSize, weight: .medium)).foregroundStyle(AppTheme.muted)
                                        .padding(.horizontal, 12).frame(minHeight: 32)
                                        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border, lineWidth: 1) }
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }.padding(.horizontal, pageGutter)
                        }.scrollIndicators(.hidden)
                    }
                }
                // TMDB search does not apply discover's filters. AniList search supports genre and sort.
                if (cleanQuery.isEmpty || kind == .anime) && kind != nil { filters.padding(.horizontal, pageGutter) }
                if query.isEmpty && !category && !library.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent searches").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Clear") { library.clearSearches() }
                                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.foreground)
                                .padding(.horizontal, 14).frame(minHeight: 44).streamifyControlSurface()
                        }.padding(.horizontal, pageGutter)
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) { ForEach(Array(library.recentSearches.prefix(5)), id: \.self) { recent in
                                Button { query = recent; focused = false } label: {
                                    Label(recent, systemImage: "clock").font(.subheadline.weight(.medium)).lineLimit(1)
                                        .padding(.horizontal, 12).frame(minHeight: 44).streamifyControlSurface()
                                }.buttonStyle(.plain).foregroundStyle(AppTheme.muted)
                                    .contextMenu { Button("Remove search", role: .destructive) { library.removeSearch(recent) } }
                                    .accessibilityAction(named: Text("Remove search")) { library.removeSearch(recent) }
                            } }.padding(.horizontal, pageGutter)
                        }.scrollIndicators(.hidden)
                    }
                }
                if cleanQuery.isEmpty || kind == .anime {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            Pill(title: "Popular", selected: !topRated) { topRated = false }
                            Pill(title: "Top rated", selected: topRated) { topRated = true }
                        }.padding(.horizontal, pageGutter)
                    }.scrollIndicators(.hidden)
                }
                if category && cleanQuery.isEmpty && !model.items.isEmpty {
                    FeaturedCarousel(items: Array(model.items.prefix(1)), visible: false)
                    PosterRail(title: "\(topRated ? "Top rated" : "Popular") \(kind?.title.lowercased() ?? "titles")", items: Array(model.items.dropFirst().prefix(19)))
                }
                if category || !cleanQuery.isEmpty {
                    SectionHeading(title: cleanQuery.isEmpty ? "Explore \(kind?.title ?? "titles")" : "Search results",
                                   subtitle: cleanQuery.isEmpty ? nil : "\(kind == .anime ? "Anime" : "Movies and series") matching “\(cleanQuery)”")
                        .padding(.horizontal, pageGutter)
                }
                PosterGrid(items: model.items).padding(.horizontal, pageGutter)
                if model.loading { ProgressView("Loading titles…").frame(maxWidth: .infinity).padding(20) }
                if let error = model.error {
                    InlineError(message: error) { if model.items.isEmpty { revision += 1 } else { Task { await load(first: false) } } }.padding(.horizontal, pageGutter)
                }
                if !model.loading && model.error == nil && model.items.isEmpty {
                    StateMessage(symbol: "magnifyingglass", title: "No titles found", message: "Try another search or adjust your filters.").padding(.horizontal, pageGutter)
                }
                if model.page < model.totalPages && !model.items.isEmpty && model.error == nil {
                    Button("Load more") { Task { await load(first: false) } }
                        .buttonStyle(SecondaryButtonStyle()).disabled(model.loading).padding(.horizontal, pageGutter)
                }
                Text(kind == .anime ? "Anime catalog by AniList" : "Film and series data by TMDB")
                    .font(.caption2).foregroundStyle(AppTheme.muted).padding(.horizontal, pageGutter)
            }.padding(.top, 12).padding(.bottom, 24)
        }
        .accessibilityIdentifier(category ? "category-catalog-\(kind?.rawValue ?? "all")" : "browse-catalog")
        .scrollDismissesKeyboard(.interactively)
        .background {
            if category {
                StreamifyRootBackdrop()
            }
        }
        .task(id: requestKey) {
            model.reset()
            do { try await Task.sleep(for: .milliseconds(cleanQuery.isEmpty ? 0 : 350)); try Task.checkCancellation() }
            catch { return }
            await load(first: true)
        }
        .task(id: "\(kind?.rawValue ?? "all"):\(settings.tmdbToken)") {
            genre = 0; provider = 0; animeGenre = ""
            guard let kind, kind != .anime else { model.genres = []; return }
            model.genres = []
            do {
                let genres = try await settings.client.genres(kind: kind)
                try Task.checkCancellation()
                model.genres = genres
            } catch {
                if !Task.isCancelled { model.genres = [] }
            }
        }
        .onChange(of: focused) { _, active in if !active { library.rememberSearch(cleanQuery) } }
        .onDisappear { library.rememberSearch(cleanQuery) }
        .refreshable { await load(first: true) }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                genreMenu
                if kind != .anime { providerMenu }
            }
        }.scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var genreMenu: some View {
        if kind == .anime {
            Menu {
                Picker("Genre", selection: $animeGenre) { Text("All genres").tag(""); ForEach(animeGenres, id: \.self) { Text($0).tag($0) } }
            } label: { genreSelectLabel(animeGenre.isEmpty ? (category ? "Categories" : "All genres") : animeGenre) }
                .buttonStyle(.plain).accessibilityLabel("Genre, \(animeGenre.isEmpty ? "All genres" : animeGenre)")
        } else {
            Menu {
                Picker("Genre", selection: $genre) { Text("All genres").tag(0); ForEach(model.genres) { Text($0.name).tag($0.id) } }
            } label: { genreSelectLabel(model.genres.first { $0.id == genre }?.name ?? (category ? "Categories" : "All genres")) }
                .buttonStyle(.plain).accessibilityLabel("Genre, \(model.genres.first { $0.id == genre }?.name ?? "All genres")")
        }
    }

    private func genreSelectLabel(_ title: String) -> some View {
        StreamifySelectLabel(title: title)
    }

    private var providerMenu: some View {
        Menu {
            Picker("Provider", selection: $provider) { ForEach(providers, id: \.0) { Text($0.1).tag($0.0) } }
        } label: { StreamifySelectLabel(title: providers.first { $0.0 == provider }?.1 ?? "All providers") }
            .buttonStyle(.plain).accessibilityLabel("Provider, \(providers.first { $0.0 == provider }?.1 ?? "All providers")")
    }

    private func load(first: Bool) async {
        await model.load(client: settings.client, kind: kind, query: cleanQuery, genre: genre,
                         animeGenre: animeGenre, provider: provider, topRated: topRated, first: first)
    }
}

@MainActor
struct CategoryView: View {
    let kind: MediaKind
    var body: some View {
        BrowseView(initialKind: kind, category: true).navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}
