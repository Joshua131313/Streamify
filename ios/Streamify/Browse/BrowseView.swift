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
    private var requestKey: String { "\(kind?.rawValue ?? "all")-\(cleanQuery)-\(genre)-\(animeGenre)-\(provider)-\(topRated)-\(revision)-\(settings.tmdbToken)" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if !category {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                        TextField(kind == .anime ? "Search anime" : "Movies, shows, and more", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($focused)
                            .onSubmit { library.rememberSearch(cleanQuery); focused = false }
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted) }.accessibilityLabel("Clear search")
                        }
                    }.padding(15).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            Pill(title: "All", selected: kind == nil) { kind = nil }
                            ForEach(MediaKind.allCases) { value in
                                Pill(title: value.title, selected: kind == value) { kind = value }
                            }
                        }.padding(.horizontal, 20)
                    }.scrollIndicators(.hidden)
                }
                if query.isEmpty && !category && !library.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeading(title: "Recent searches")
                            Button("Clear") { library.clearSearches() }.font(.caption).frame(minHeight: 44)
                        }
                        ForEach(Array(library.recentSearches.prefix(5)), id: \.self) { recent in
                            HStack {
                                Button { query = recent; focused = false } label: {
                                    Label(recent, systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                                }.tint(.primary)
                                Button { library.removeSearch(recent) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                    .foregroundStyle(AppTheme.muted).accessibilityLabel("Remove search \(recent)")
                            }.font(.subheadline)
                        }
                    }.padding(.horizontal, 20)
                }
                // TMDB's search endpoints do not apply discover's genre/provider filters.
                // AniList search does support its genre and sort arguments.
                if cleanQuery.isEmpty || kind == .anime { filters.padding(.horizontal, 20) }
                SectionHeading(title: cleanQuery.isEmpty ? (category ? "Explore \(kind?.title ?? "titles")" : topRated ? "Top rated" : "Popular right now") : "Results for “\(cleanQuery)”")
                    .padding(.horizontal, 20)
                PosterGrid(items: model.items).padding(.horizontal, 20)
                if model.loading { ProgressView("Loading titles…").frame(maxWidth: .infinity).padding(20) }
                if let error = model.error {
                    InlineError(message: error) { if model.items.isEmpty { revision += 1 } else { Task { await load(first: false) } } }.padding(.horizontal, 20)
                }
                if !model.loading && model.error == nil && model.items.isEmpty {
                    StateMessage(symbol: "magnifyingglass", title: "No titles found", message: "Try another search or adjust your filters.").padding(.horizontal, 20)
                }
                if model.page < model.totalPages && !model.items.isEmpty && model.error == nil {
                    Button("Load more") { Task { await load(first: false) } }
                        .buttonStyle(SecondaryButtonStyle()).disabled(model.loading).padding(.horizontal, 20)
                }
                Text(kind == .anime ? "Anime catalog by AniList" : "Film and series data by TMDB")
                    .font(.caption2).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
            }.padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.canvas)
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
                Picker("Sort", selection: $topRated) { Text("Popular").tag(false); Text("Top rated").tag(true) }
                if kind == .anime {
                    Picker("Genre", selection: $animeGenre) { Text("All genres").tag(""); ForEach(animeGenres, id: \.self) { Text($0).tag($0) } }
                } else if kind != nil {
                    Picker("Genre", selection: $genre) { Text("All genres").tag(0); ForEach(model.genres) { Text($0.name).tag($0.id) } }
                    Picker("Provider", selection: $provider) { ForEach(providers, id: \.0) { Text($0.1).tag($0.0) } }
                }
            }.pickerStyle(.menu).font(.subheadline).tint(.primary)
        }.scrollIndicators(.hidden)
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
    }
}
