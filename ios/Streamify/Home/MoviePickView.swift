import SwiftUI

struct MoviePickShortcut: View {
    @State private var showing = false
    @State private var details: MediaItem?
    @State private var pendingDetails: MediaItem?
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "shuffle").font(.title2).foregroundStyle(AppTheme.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick for me").font(.headline)
                    Text("Choose a genre. Find your next movie.").font(.caption).foregroundStyle(AppTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.headline)
            }.padding(18).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(HapticCardButtonStyle(cornerRadius: 16)).padding(.horizontal, 20)
            .accessibilityIdentifier("home-pick-for-me")
            .sheet(isPresented: $showing, onDismiss: { details = pendingDetails; pendingDetails = nil }) {
                MoviePickView { media in pendingDetails = media; showing = false }
            }
            .fullScreenCover(item: $details) { media in
                NavigationStack { MediaDetailView(media: media) }.presentationBackground(AppTheme.canvas)
            }
    }
}

struct MoviePickView: View {
    let open: (MediaItem) -> Void
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var genre: CatalogGenre?
    @State private var pool: MoviePickPool?
    @State private var picked: MediaItem?
    @State private var shown = Set<String>()
    @State private var loading = false
    @State private var error: String?
    @State private var request: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let picked {
                        result(picked)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What are you in the mood for?").font(.title2.bold())
                            Text("Movies from 2000 onward, with a little inspiration from your watch history. Already watched titles stay out.")
                                .font(.subheadline).foregroundStyle(AppTheme.muted)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                            ForEach(MoviePickPolicy.genres) { item in
                                Button {
                                    request = nil; loading = false; genre = item; pool = nil; shown = []; error = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(item.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        Spacer(minLength: 0)
                                        if genre == item { Image(systemName: "checkmark").font(.caption.bold()) }
                                    }.padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52)
                                        .foregroundStyle(genre == item ? AppTheme.canvas : AppTheme.foreground)
                                        .background(genre == item ? AppTheme.foreground : AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(HapticCardButtonStyle(cornerRadius: 12))
                                    .accessibilityAddTraits(genre == item ? .isSelected : [])
                                    .accessibilityIdentifier("movie-pick-genre-\(item.id)")
                            }
                        }
                        Button { request = UUID() } label: {
                            HStack { if loading { ProgressView() }; Label(loading ? "Finding your movie…" : "Pick for me", systemImage: "shuffle") }
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle()).disabled(genre == nil || loading)
                            .accessibilityIdentifier("movie-pick-draw")
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(AppTheme.muted).accessibilityIdentifier("movie-pick-error") }
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
                .navigationTitle("Pick for me").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: request) { if request != nil { await draw() } }
        }.presentationDragIndicator(.visible).presentationDetents([.large])
    }

    private func result(_ media: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            RemoteArtwork(url: media.backdropURL ?? media.posterURL).aspectRatio(16 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 8) {
                Text(genre?.name.uppercased() ?? "YOUR PICK").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(AppTheme.muted)
                Text(media.title).font(.title.bold()).accessibilityIdentifier("movie-pick-result")
                Text("\(media.year) · ★ \(media.rating.formatted(.number.precision(.fractionLength(1))))").font(.subheadline).foregroundStyle(AppTheme.muted)
                Text(media.overview).font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(5)
            }
            Button { open(media) } label: { Label("View movie", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("movie-pick-open")
            HStack(spacing: 12) {
                Button { request = UUID() } label: { Label("Pick another", systemImage: "shuffle").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle()).disabled(loading).accessibilityIdentifier("movie-pick-another")
                Button { picked = nil; error = nil } label: { Text("Change genre").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle()).disabled(loading).accessibilityIdentifier("movie-pick-change")
            }
            if loading { ProgressView("Finding your movie…").frame(maxWidth: .infinity) }
        }
    }

    @MainActor private func draw() async {
        guard let genre else { return }
        guard let currentRequest = request else { return }
        loading = true; error = nil
        defer { if request == currentRequest { loading = false } }
        do {
            let current: MoviePickPool
            if let pool { current = pool }
            else { current = try await settings.client.moviePickPool(genre: genre.id, history: library.history) }
            try Task.checkCancellation()
            pool = current
            guard let choice = MoviePickPolicy.choose(current.items, history: library.history, recommended: current.recommended, excluding: shown) else {
                error = "You’ve seen this batch. Choose another genre for more movies."
                return
            }
            shown.insert(choice.key)
            withAnimation(.easeInOut(duration: 0.22)) { picked = choice }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = "Couldn’t find a movie just now. \(error.localizedDescription)" } }
    }
}
