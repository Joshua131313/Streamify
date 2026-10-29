import SwiftUI
import GoogleSignInSwift

@MainActor
struct LibraryView: View {
    var favoritesRequest: UUID? = nil
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var profiles: ProfileStore
    @State private var history = false
    @State private var query = ""
    @State private var kind: MediaKind?
    @State private var player: WatchEntry?
    @State private var playbackOrigin: MediaPlaybackOrigin?
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
                }.buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.foreground)
                Label("\(profiles.activeProfile?.name ?? "My profile") · on this iPhone", systemImage: "iphone").font(.caption).foregroundStyle(AppTheme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Pill(title: "Saved · \(library.saved.count)", selected: !history) { history = false }
                        Pill(title: "History · \(library.history.count)", selected: history) { history = true }
                    }
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                    TextField(history ? "Find in history" : "Find in My list", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }
                            .buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.muted).accessibilityLabel("Clear search")
                    }
                }.padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0).frame(minHeight: 48).streamifyControlSurface()
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
                            .streamifyControlSurface().buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.accent)
                    }
                }
                if history {
                    let entries = library.history.filter { matches($0.media) }
                    if entries.isEmpty { emptyState }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 560), spacing: 16)], spacing: 12) {
                        ForEach(entries) { entry in
                            MediaPlaybackOriginCard { origin in
                                WatchHistoryCard(entry: entry, resume: { playbackOrigin = origin; player = entry })
                            }
                        }
                    }
                } else {
                    let items = library.saved.filter(matches)
                    if items.isEmpty { emptyState }
                    PosterGrid(items: items)
                }
                Text("Saved on this \(AdaptiveLayout.deviceName)").font(.caption).foregroundStyle(AppTheme.muted)
            }.padding(20).padding(.bottom, 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(AppTheme.foreground)
        .onChange(of: favoritesRequest, initial: true) { _, request in
            guard request != nil else { return }
            history = false; query = ""; kind = nil
            player = nil; showDownloads = false; clearHistory = false
        }
        .sheet(isPresented: $showDownloads) { NavigationStack { DownloadsView() } }
        .fullScreenCover(item: $player) { MediaPlayerView(media: $0.media, season: $0.season, episode: $0.episode, origin: playbackOrigin) }
        .confirmationDialog("Clear your watch history on this \(AdaptiveLayout.deviceName)?", isPresented: $clearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { library.clearHistory() }
        }
    }

    private var emptyState: some View {
        let unfiltered = query.isEmpty && kind == nil
        return StateMessage(symbol: history ? "clock.arrow.circlepath" : "bookmark", title: unfiltered ? (history ? "Your story starts here." : "Keep the good ones.") : "No matching titles",
                            message: unfiltered ? (history ? "Titles you open in the player will appear here." : "Tap My list on a title to save it for later.") : "Try a different title or media type.")
    }
}

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var api = ""
    @State private var serverID = ""
    @State private var error: String?
    @State private var showToken = false
    @ObservedObject private var liveAlerts = SportsLiveAlerts.shared

    var body: some View {
        Form {
            Section("Your account") {
                NavigationLink { AccountView() } label: { Label("Account & preferences", systemImage: "person.crop.circle") }
            }.listRowBackground(AppTheme.panel)
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0) } }.pickerStyle(.segmented).disabled(!profiles.canEditProfiles)
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
                Text("Your catalog key is stored in the device Keychain. Leave the sports backend empty to use ESPN directly.")
            }.listRowBackground(AppTheme.panel)
            Section("Default video provider") {
                Picker("Provider", selection: $serverID) { ForEach(settings.servers) { Text($0.label).tag($0.id) } }.tint(AppTheme.foreground).disabled(!profiles.canEditProfiles)
            }.listRowBackground(AppTheme.panel)
            Section {
                Toggle("Followed teams go live", isOn: Binding(get: { settings.liveTeamAlerts }, set: { enabled in
                    if !enabled { settings.liveTeamAlerts = false }
                    else { Task { settings.liveTeamAlerts = await liveAlerts.authorize() } }
                })).tint(AppTheme.foreground).accessibilityIdentifier("sports-live-alerts-toggle")
                if let status = liveAlerts.status { Text(status).font(.caption).foregroundStyle(AppTheme.muted) }
            } header: { Text("Sports alerts") } footer: {
                if !SportsLiveAlerts.remotePushConfigured {
                    Text("Alerts while the app is closed need Apple push signing. This sideloaded build can alert you when Streamify checks scores.")
                }
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
        if profiles.canEditProfiles { settings.serverID = serverID }
        dismiss()
    }
}

@MainActor
struct AccountView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var account: AccountSession
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var registering = false
    @State private var confirmReload = false
    private enum AccountField: Hashable { case email, password }
    @FocusState private var focusedField: AccountField?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    ProfileAvatarView(avatar: profiles.activeProfile?.avatar ?? .crimson, size: 72)
                    Text(profiles.activeProfile?.name ?? "My profile").font(.title2.bold())
                        .accessibilityIdentifier("account-profile-name")
                    Text("Your favorites, your teams, your next watch.").font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
                    HStack(spacing: 24) {
                        accountCount(library.saved.count, "Saved")
                        accountCount(library.history.count, "Watched")
                        accountCount(library.followedTeams.count, "Teams")
                    }.padding(.top, 4)
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: AdaptiveLayout.deviceSymbol).font(.subheadline).foregroundStyle(AppTheme.muted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.identity == nil ? "Saved on this \(AdaptiveLayout.deviceName)" : "Your account, your profiles").font(.caption.weight(.semibold))
                            Text(account.identity == nil ? "Sign in to sync profiles, appearance, video provider, favorite genres, and followed teams." : "Profiles, appearance, video provider, favorite genres, and followed teams sync with your account. Your list, history, and downloads stay on this device.")
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 4)
                }.frame(maxWidth: .infinity).padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 0.5) }
                Button { profiles.showChooser() } label: {
                    Label("Switch profiles", systemImage: "person.2").frame(maxWidth: .infinity)
                }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("switch-profiles")
                accountAccess
                NavigationLink { PreferencesView() } label: {
                    HStack {
                        Label("Your favorite genres", systemImage: "slider.horizontal.3").font(.headline)
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 1) }
                }.buttonStyle(HapticPlainButtonStyle()).disabled(!profiles.canEditProfiles)
                Text("Follow teams from Sports to find their games in the Following filter.").font(.subheadline).foregroundStyle(AppTheme.muted)
            }.padding(20).streamifyReadableWidth()
        }
        .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground).navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { password = "" }
        .confirmationDialog("Reload account profiles?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Reload account profiles") { Task { await profiles.reloadCloudProfiles() } }
        } message: { Text("This replaces pending profile preferences with the account’s saved version. A local recovery copy is kept; your saved list and watch history stay on this iPhone.") }
    }

    @ViewBuilder private var accountAccess: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let identity = account.identity {
                Label(identity.email ?? "Signed in", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline).accessibilityIdentifier("account-email-label")
                Text(profiles.syncStatus.title).font(.subheadline).foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("account-sync-status")
                switch profiles.syncStatus {
                case .failed, .pending:
                    Button("Retry sync") { Task { await profiles.retrySync() } }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("account-sync-retry")
                case .conflict:
                    Button("Reload account profiles") { confirmReload = true }.buttonStyle(SecondaryButtonStyle())
                case .loading, .syncing:
                    ProgressView().tint(AppTheme.foreground)
                default: EmptyView()
                }
                Button("Sign out") { Task { await account.signOut() } }
                    .buttonStyle(SecondaryButtonStyle()).disabled(account.isWorking)
                    .accessibilityIdentifier("account-sign-out")
                Text("Signing out returns to your separate guest profiles. Any pending account changes remain saved for your next sign-in.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            } else {
                Text(registering ? "Create your account" : "Sign in to Streamify").font(.headline)
                GoogleSignInButton(scheme: .light, style: .wide, state: account.isWorking ? .disabled : .normal) {
                    AppHaptics.tap(.primary)
                    Task { password = ""; await account.signInWithGoogle() }
                }.frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityIdentifier("account-google-sign-in")
                HStack(spacing: 12) {
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                    Text("or use email").font(.caption).foregroundStyle(AppTheme.muted).fixedSize()
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                }
                TextField("Email address", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email).submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(14).streamifyControlSurface().accessibilityIdentifier("account-email")
                SecureField("Password", text: $password)
                    .textContentType(registering ? .newPassword : .password)
                    .focused($focusedField, equals: .password).submitLabel(.go).onSubmit(submitAccount)
                    .padding(14).streamifyControlSurface().accessibilityIdentifier("account-password")
                Button(action: submitAccount) {
                    HStack { if account.isWorking { ProgressView().tint(.black) }; Text(registering ? "Create account" : "Sign in") }.frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButtonStyle()).disabled(account.isWorking).accessibilityIdentifier("account-submit")
                HStack {
                    Button { registering.toggle(); password = "" } label: {
                        Text(registering ? "Already have an account?" : "Create account")
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("account-mode")
                    Spacer()
                    if !registering {
                        Button { Task { await account.resetPassword(email: email) } } label: {
                            Text("Forgot password?").frame(minHeight: 44).contentShape(Rectangle())
                        }
                            .accessibilityIdentifier("account-reset-password")
                    }
                }.font(.caption.weight(.semibold)).buttonStyle(HapticPlainButtonStyle()).disabled(account.isWorking)
                Text("Use your Streamify account email and password. Existing account profiles load first; a new account copies these guest profiles while keeping the originals here.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            if let error = account.error { Text(error).font(.subheadline).foregroundStyle(AppTheme.accent).accessibilityIdentifier("account-auth-error") }
            if let message = account.message { Text(message).font(.subheadline).foregroundStyle(AppTheme.muted).accessibilityIdentifier("account-auth-message") }
        }.padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 0.5) }
    }

    private func accountCount(_ count: Int, _ title: String) -> some View {
        VStack(spacing: 4) { Text(String(count)).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity)
    }
    private func submitAccount() {
        let enteredPassword = password, enteredEmail = email, createAccount = registering
        password = ""; focusedField = nil
        Task {
            if createAccount { await account.register(email: enteredEmail, password: enteredPassword) }
            else { await account.signIn(email: enteredEmail, password: enteredPassword) }
        }
    }
}

@MainActor
struct PreferencesView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 68
    private let genres = [(28,"Action"),(12,"Adventure"),(16,"Animation"),(35,"Comedy"),(80,"Crime"),(99,"Documentary"),(18,"Drama"),(10751,"Family"),(14,"Fantasy"),(27,"Horror"),(9648,"Mystery"),(10749,"Romance"),(878,"Sci-Fi"),(53,"Thriller")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(title: "What do you love?", subtitle: "Choose a few genres to shape your For you recommendations.")
                HStack {
                    Text("\(library.favoriteGenres.count) selected").font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted)
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(genres, id: \.0) { genre in
                        let selected = library.favoriteGenres.contains(genre.0)
                        Button { library.setGenre(genre.0) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: symbol(for: genre.0)).font(.system(size: 18, weight: .regular)).frame(width: 24)
                                Text(genre.1).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: tileHeight, alignment: .leading)
                            .foregroundStyle(AppTheme.foreground)
                            .background(selected ? AppTheme.foreground.opacity(0.10) : AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? AppTheme.foreground.opacity(0.5) : AppTheme.border, lineWidth: selected ? 1.2 : 0.7) }
                            .overlay(alignment: .topTrailing) {
                                if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).padding(7).accessibilityHidden(true) }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(HapticPlainButtonStyle()).disabled(!profiles.canEditProfiles)
                            .accessibilityLabel(genre.1).accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("favorite-genre-\(genre.0)")
                    }
                }
            }.padding(20).streamifyReadableWidth(900)
        }.background(AppTheme.canvas).navigationTitle("Favorite genres").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("favorite-genres-screen")
    }

    private func symbol(for id: Int) -> String {
        switch id {
        case 28: "bolt"; case 12: "map"; case 16: "sparkles"; case 35: "face.smiling"
        case 80: "touchid"; case 99: "camera"; case 18: "theatermasks"; case 10751: "person.2"
        case 14: "wand.and.stars"; case 27: "moon"; case 9648: "magnifyingglass"; case 10749: "heart"
        case 878: "globe.americas"; default: "film"
        }
    }
}
