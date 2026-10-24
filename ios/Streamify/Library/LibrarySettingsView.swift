import SwiftUI

@MainActor
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var history = false
    @State private var query = ""
    @State private var kind: MediaKind?
    @State private var player: WatchEntry?
    @State private var clearHistory = false
    @State private var showDownloads = false

    private func matches(_ media: MediaItem) -> Bool {
        (kind == nil || media.kind == kind) && (query.isEmpty || media.title.localizedCaseInsensitiveContains(query))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Made for your downtime", subtitle: "Your saved favorites and everything you’ve started.")
                Button { showDownloads = true } label: {
                    Label("View downloads", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 48)
                        .streamifyControlSurface()
                }.buttonStyle(.plain).foregroundStyle(AppTheme.foreground)
                Label("Guest library · on this iPhone", systemImage: "iphone").font(.caption).foregroundStyle(AppTheme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Pill(title: "Saved · \(library.saved.count)", selected: !history) { history = false }
                        Pill(title: "History · \(library.history.count)", selected: history) { history = true }
                    }
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                    TextField(history ? "Find in history" : "Find in My list", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                }.padding(14).streamifyControlSurface(cornerRadius: 14)
                HStack {
                    Menu {
                        Button { kind = nil } label: {
                            if kind == nil { Label("All titles", systemImage: "checkmark") } else { Text("All titles") }
                        }
                        ForEach(MediaKind.allCases) { item in
                            Button { kind = item } label: {
                                if kind == item { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                            }
                        }
                    } label: { StreamifySelectLabel(title: kind?.title ?? "All titles", symbol: "line.3.horizontal.decrease") }
                        .accessibilityLabel("Filter library by type")
                    Spacer()
                    if history && !library.history.isEmpty {
                        Button("Clear history", role: .destructive) { clearHistory = true }
                            .font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                            .streamifyControlSurface().buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                    }
                }
                if history {
                    let entries = library.history.filter { matches($0.media) }
                    if entries.isEmpty { emptyState }
                    LazyVStack(spacing: 16) {
                        ForEach(entries) { entry in
                            HStack(spacing: 14) {
                                MediaDetailLink(media: entry.media) {
                                    RemoteArtwork(url: entry.media.posterURL).frame(width: 64, height: 96).clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    MediaDetailLink(media: entry.media) { Text(entry.media.title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2) }
                                    if entry.media.kind != .movie { Text("S\(entry.season) · E\(entry.episode)").font(.caption).foregroundStyle(AppTheme.muted) }
                                    Text(entry.watchedAt, style: .date).font(.caption2).foregroundStyle(AppTheme.muted)
                                    if entry.durationSeconds > 0 {
                                        ProgressView(value: entry.progress).tint(AppTheme.accent)
                                        Text(entry.completed ? "Watched" : "\(Int(ceil(max(0, entry.durationSeconds - entry.positionSeconds) / 60))) min left")
                                            .font(.caption2).foregroundStyle(AppTheme.muted)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button { player = entry } label: { Image(systemName: "play.circle.fill").font(.title).frame(width: 44, height: 44) }.accessibilityLabel("Resume \(entry.media.title)")
                                Menu {
                                    Button("Remove from history", systemImage: "trash", role: .destructive) { library.removeHistory(entry) }
                                    Button(library.isSaved(entry.media) ? "Remove from My list" : "Add to My list", systemImage: "bookmark") { library.toggleSaved(entry.media) }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Actions for \(entry.media.title)")
                            }.padding(14).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.border, lineWidth: 1) }
                        }
                    }
                } else {
                    let items = library.saved.filter(matches)
                    if items.isEmpty { emptyState }
                    PosterGrid(items: items)
                }
                Text("Saved on this iPhone").font(.caption).foregroundStyle(AppTheme.muted)
            }.padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.canvas)
        .foregroundStyle(AppTheme.foreground)
        .sheet(isPresented: $showDownloads) { NavigationStack { DownloadsView() } }
        .fullScreenCover(item: $player) { MediaPlayerView(media: $0.media, season: $0.season, episode: $0.episode) }
        .confirmationDialog("Clear your watch history on this iPhone?", isPresented: $clearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { library.clearHistory() }
        }
    }

    private var emptyState: some View {
        StateMessage(symbol: history ? "clock.arrow.circlepath" : "bookmark", title: query.isEmpty ? (history ? "Your story starts here." : "Keep the good ones.") : "No matching titles",
                     message: query.isEmpty ? (history ? "Titles you open in the player will appear here." : "Tap My list on a title to save it for later.") : "Try a different title or media type.")
    }
}

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var api = ""
    @State private var serverID = ""
    @State private var error: String?
    @State private var showToken = false

    var body: some View {
        Form {
            Section("Your account") {
                NavigationLink { AccountView() } label: { Label("Account & preferences", systemImage: "person.crop.circle") }
            }.listRowBackground(AppTheme.panel)
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            }.listRowBackground(AppTheme.panel)
            Section {
                HStack {
                    Group {
                        if showToken { TextField("TMDB API key or read access token", text: $token) }
                        else { SecureField("TMDB API key or read access token", text: $token) }
                    }.textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { showToken.toggle() } label: { Image(systemName: showToken ? "eye.slash" : "eye").frame(width: 44, height: 44) }.accessibilityLabel(showToken ? "Hide token" : "Show token")
                }
                Link("Get a TMDB API key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                TextField("Sports backend URL (optional)", text: $api).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("Catalog & connections") } footer: {
                Text("Your catalog key is stored in the iPhone Keychain. Leave the sports backend empty to use ESPN directly.")
            }.listRowBackground(AppTheme.panel)
            Section("Default video provider") {
                Picker("Provider", selection: $serverID) { ForEach(settings.servers) { Text($0.label).tag($0.id) } }.tint(AppTheme.foreground)
            }.listRowBackground(AppTheme.panel)
            if let error { Section { Text(error).foregroundStyle(AppTheme.accent) }.listRowBackground(AppTheme.panel) }
            if let credentialError = settings.credentialError { Section { Text(credentialError).foregroundStyle(AppTheme.accent) }.listRowBackground(AppTheme.panel) }
            Section {
                Button("Save settings", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("save-settings")
            }.listRowBackground(AppTheme.panel)
            Section("About Streamify") {
                NavigationLink { AppUpdatesView() } label: { Label("App updates", systemImage: "arrow.down.app") }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Film and series data by TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB. Anime data by AniList. Sports data by ESPN.").font(.footnote).foregroundStyle(AppTheme.muted)
                Text("Video is supplied by external services. A source may be unavailable; choose another provider or open it in Safari.").font(.footnote).foregroundStyle(AppTheme.muted)
            }.listRowBackground(AppTheme.panel)
        }
        .scrollContentBackground(.hidden).background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { token = settings.tmdbToken; api = settings.apiBase; serverID = settings.serverID }
    }

    private func save() {
        let trimmed = api.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let url = secureURL(trimmed), let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  (c.path.isEmpty || c.path == "/"), c.query == nil, c.fragment == nil else {
                error = "Enter an HTTPS origin, such as https://example.com, without a path or query."
                return
            }
        }
        settings.tmdbToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.credentialError == nil else { return }
        settings.apiBase = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        settings.serverID = serverID
        dismiss()
    }
}

@MainActor
struct AccountView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(AppTheme.accent)
                    Text("Make yourself at home.").font(.title2.bold())
                    Text("Your favorites, your teams, your next watch.").foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
                    HStack(spacing: 24) {
                        accountCount(library.saved.count, "Saved")
                        accountCount(library.history.count, "Watched")
                        accountCount(library.followedTeams.count, "Teams")
                    }.padding(.top, 10)
                }.frame(maxWidth: .infinity).padding(24).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(AppTheme.border, lineWidth: 1) }
                StateMessage(symbol: "iphone", title: "Saved on this iPhone", message: "Account sign-in is not configured in this build. Your list, history, teams, and preferences are stored on this device.")
                NavigationLink { PreferencesView() } label: {
                    HStack {
                        Label("Your favorite genres", systemImage: "slider.horizontal.3").font(.headline)
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 1) }
                }.buttonStyle(.plain)
                Text("Follow teams from Sports to find their games in the Following filter.").font(.subheadline).foregroundStyle(AppTheme.muted)
            }.padding(20)
        }
        .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground).navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func accountCount(_ count: Int, _ title: String) -> some View {
        VStack(spacing: 4) { Text(String(count)).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity)
    }
}

@MainActor
struct PreferencesView: View {
    @EnvironmentObject private var library: LibraryStore
    private let genres = [(28,"Action"),(12,"Adventure"),(16,"Animation"),(35,"Comedy"),(80,"Crime"),(99,"Documentary"),(18,"Drama"),(10751,"Family"),(14,"Fantasy"),(27,"Horror"),(9648,"Mystery"),(10749,"Romance"),(878,"Sci-Fi"),(53,"Thriller")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(title: "What do you love?", subtitle: "Choose a few genres to shape your For you recommendations.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 12) {
                    ForEach(genres, id: \.0) { genre in
                        Pill(title: genre.1, selected: library.favoriteGenres.contains(genre.0)) { library.setGenre(genre.0) }
                    }
                }
            }.padding(20)
        }.background(AppTheme.canvas).navigationTitle("Preferences").navigationBarTitleDisplayMode(.inline)
    }
}
