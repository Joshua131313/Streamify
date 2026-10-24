import SwiftUI

@MainActor
struct CatalogSearchDialog: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = BrowseModel()
    @State private var kind: MediaKind?
    @State private var query = ""
    @State private var revision = 0
    @State private var waiting = false
    @State private var hasFocused = false
    @State private var selected: MediaItem?
    @FocusState private var focused: Bool
    @Namespace private var transition
    @ScaledMetric(relativeTo: .body) private var posterWidth: CGFloat = 104

    init(initialKind: MediaKind? = nil) { _kind = State(initialValue: initialKind) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var requestKey: String { "\(kind?.rawValue ?? "all")|\(cleanQuery)|\(settings.tmdbToken)|\(revision)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField.padding(.horizontal, 16).padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        typeFilter("All", kind: nil)
                        typeFilter("Movies", kind: .movie)
                        typeFilter("Series", kind: .tv)
                        typeFilter("Anime", kind: .anime)
                    }.padding(.horizontal, 16)
                }.padding(.vertical, 10)
                Rectangle().fill(AppTheme.border).frame(height: 0.5)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if cleanQuery.isEmpty { recentSearches }
                        else {
                            SectionHeading(title: "Search results", subtitle: "Matching “\(cleanQuery)”")
                            if waiting || model.loading && model.items.isEmpty {
                                ProgressView("Searching titles…").frame(maxWidth: .infinity).padding(.vertical, 28)
                                    .accessibilityIdentifier("catalog-search-loading")
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: posterWidth, maximum: 180), spacing: 12)], alignment: .leading, spacing: 20) {
                                ForEach(model.items, id: \.key) { media in result(media) }
                            }
                            if let error = model.error { InlineError(message: error) { revision += 1 } }
                            if !waiting && !model.loading && model.error == nil && model.items.isEmpty {
                                StateMessage(symbol: "magnifyingglass", title: "No titles found", message: "Try a different title or choose another media type.")
                            }
                            if model.page < model.totalPages && !model.items.isEmpty {
                                Button { Task { await load(first: false) } } label: {
                                    HStack(spacing: 10) {
                                        if model.loading { ProgressView().tint(AppTheme.foreground) }
                                        Text(model.loading ? "Loading more…" : "Load more")
                                    }
                                }
                                    .buttonStyle(SecondaryButtonStyle()).disabled(model.loading)
                            }
                        }
                    }.padding(16).padding(.bottom, 24)
                }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("catalog-search-results")
            }
            .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { focused = false; dismiss() }.accessibilityIdentifier("cancel-catalog-search") } }
            .task {
                guard !hasFocused else { return }
                do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation(); hasFocused = true; focused = true }
                catch { }
            }
            .task(id: requestKey) {
                let request = requestKey
                model.reset()
                guard !cleanQuery.isEmpty else { waiting = false; return }
                waiting = true
                defer { if request == requestKey { waiting = false } }
                do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation() }
                catch { return }
                await load(first: true)
            }
            .onChange(of: focused) { _, value in if !value { library.rememberSearch(cleanQuery) } }
            .onDisappear { library.rememberSearch(cleanQuery) }
            .fullScreenCover(item: $selected) { media in
                if #available(iOS 18, *), !reduceMotion {
                    NavigationStack { MediaDetailView(media: media) }
                        .navigationTransition(.zoom(sourceID: media.key, in: transition))
                        .presentationBackground(AppTheme.canvas)
                } else {
                    NavigationStack { MediaDetailView(media: media) }.presentationBackground(AppTheme.canvas)
                }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
            TextField("Movies, series & anime", text: $query)
                .font(.subheadline).focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .accessibilityIdentifier("browse-search")
                .onSubmit { library.rememberSearch(cleanQuery); focused = false }
            if !query.isEmpty {
                Button { query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.muted).accessibilityLabel("Clear search").accessibilityIdentifier("clear-catalog-search")
            }
        }.padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0).frame(minHeight: 52).streamifyControlSurface()
    }

    private func typeFilter(_ title: String, kind value: MediaKind?) -> some View {
        Pill(title: title, selected: kind == value) { kind = value }
            .accessibilityIdentifier("catalog-search-kind-\(value?.rawValue ?? "all")")
    }

    @ViewBuilder private var recentSearches: some View {
        if !library.recentSearches.isEmpty {
            HStack {
                Text("Recent searches").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Button("Clear") { library.clearSearches() }.font(.caption.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("clear-catalog-recents")
            }
            ForEach(Array(library.recentSearches.prefix(10)), id: \.self) { recent in
                Button { query = recent; library.rememberSearch(recent); focused = false } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(AppTheme.muted)
                        Text(recent).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(AppTheme.muted)
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(HapticPlainButtonStyle())
                    .contextMenu { Button("Remove search", role: .destructive) { library.removeSearch(recent) } }
                    .accessibilityAction(named: Text("Remove search")) { library.removeSearch(recent) }
            }
        } else {
            StateMessage(symbol: "magnifyingglass", title: "Find your next favorite", message: "Search a movie, series, or anime by title.")
        }
    }

    @ViewBuilder private func result(_ media: MediaItem) -> some View {
        if #available(iOS 18, *) {
            resultButton(media).matchedTransitionSource(id: media.key, in: transition)
        } else { resultButton(media) }
    }
    private func resultButton(_ media: MediaItem) -> some View {
        Button {
            focused = false
            library.rememberSearch(cleanQuery)
            selected = media
        } label: { PosterContent(media: media, roomy: true).contentShape(Rectangle()) }
            .buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("media-link-\(media.key)")
    }

    private func load(first: Bool) async {
        guard !cleanQuery.isEmpty else { return }
        await model.load(client: settings.client, kind: kind, query: cleanQuery, genre: 0, animeGenre: "", provider: 0, topRated: false, first: first, includeAnimeSearch: true)
    }
}
