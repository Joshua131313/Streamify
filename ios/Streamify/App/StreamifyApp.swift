import SwiftUI

@main
@MainActor
struct StreamifyApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var appDelegate
    @StateObject private var profiles: ProfileStore
    @StateObject private var account: AccountSession
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var sportsPlayback = SportsPlaybackSession()
    @StateObject private var quickActions = AppQuickActionRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SportsChatBootstrap.configure()
        SportsLiveAlerts.shared.bootstrap()
        #if DEBUG
        if PreviewFixtures.enabled { PreviewFixtures.install() }
        let localAccount = PreviewFixtures.enabled && ProcessInfo.processInfo.arguments.contains("--ui-account-success")
        _account = StateObject(wrappedValue: AccountSession(client: localAccount ? PreviewAccountClient() : nil))
        let profileStore = ProfileStore(defaults: PreviewFixtures.enabled ? PreviewFixtures.defaults : .standard,
            chooseOnLaunch: !PreviewFixtures.enabled || ProcessInfo.processInfo.arguments.contains("--ui-profile-chooser"),
            backend: localAccount ? PreviewProfileBackend() : nil)
        if PreviewFixtures.enabled { PreviewFixtures.seedLibrary(profileStore.library) }
        if PreviewFixtures.enabled && ProcessInfo.processInfo.arguments.contains("--ui-profile-quick-switch") {
            profileStore.settings.appearance = ProcessInfo.processInfo.arguments.contains("--ui-glass-dark") ? "Dark" : "Light"
            try? profileStore.add(name: "Alex", avatar: .ocean)
        }
        _profiles = StateObject(wrappedValue: profileStore)
        if PreviewFixtures.enabled {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--ui-quick-action"), arguments.indices.contains(index + 1),
               let action = AppQuickAction.allCases.first(where: { $0.rawValue.split(separator: ".").last.map(String.init) == arguments[index + 1] }) {
                AppQuickActionRouter.shared.enqueue(action.destination)
            }
        }
        #else
        _account = StateObject(wrappedValue: AccountSession())
        _profiles = StateObject(wrappedValue: ProfileStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ProfileAppGate()
                .buttonStyle(HapticAutomaticButtonStyle())
                .environmentObject(profiles.settings)
                .environmentObject(profiles)
                .environmentObject(account)
                .environmentObject(profiles.library)
                .environmentObject(downloads)
                .environmentObject(sportsPlayback)
                .environmentObject(quickActions)
                .background { SportsPlaybackHost(session: sportsPlayback, apiBase: profiles.settings.apiBase).frame(width: 0, height: 0) }
                .overlay(alignment: .bottomLeading) {
                    #if DEBUG
                    if PreviewNetworkActivity.enabled { PreviewNetworkReport() }
                    #endif
                }
                .tint(AppTheme.foreground)
                .onOpenURL { if !GoogleAccountSignIn.handle($0) { quickActions.enqueue(url: $0) } }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await SportsGameTracker.shared.refreshWhileActive()
                }
                .onAppear {
                    sportsPlayback.configureSourcePreference(
                        read: { profiles.settings.sportsServerPreference },
                        write: { profiles.settings.sportsServerPreference = $0 })
                    #if DEBUG
                    if PreviewFixtures.enabled {
                        PreviewFixtures.seedDownloads(downloads)
                    }
                    #endif
                }
        }
    }
}

@MainActor
private struct ProfileAppGate: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var account: AccountSession
    @EnvironmentObject private var sportsPlayback: SportsPlaybackSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasEnteredApp = false
    @State private var showsChooser = true
    @State private var rootDimmed = false
    @State private var changingProfile = false
    @State private var initialized = false
    @State private var chooserReset = 0
    @State private var homeRevision = 0

    private var returningFromSignIn: Bool {
        account.isSigningIn || (account.homeIntent?.uid != nil && account.homeIntent?.uid == account.identity?.uid)
    }

    private var isLoadingProfiles: Bool {
        !account.isResolved || profiles.ownerUID != account.identity?.uid || !profiles.canEditProfiles ||
            (returningFromSignIn && profiles.requiresSelection)
    }
    private var handoffAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.18 : 0.42)
    }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            Group {
                if !isLoadingProfiles && (hasEnteredApp || !profiles.requiresSelection) {
                    RootView(onSelectProfile: selectProfile).id("\(profiles.contextID):\(homeRevision)")
                        .environment(\.scenePhase, profiles.requiresSelection || showsChooser || changingProfile ? .inactive : scenePhase)
                        .onAppear { hasEnteredApp = true }
                        .opacity(showsChooser || rootDimmed ? 0 : 1)
                        .scaleEffect(!reduceMotion && (showsChooser || rootDimmed) ? 0.985 : 1)
                }
            }
            .allowsHitTesting(!isLoadingProfiles && !profiles.requiresSelection && !showsChooser && !changingProfile)
            .accessibilityHidden(isLoadingProfiles || profiles.requiresSelection || showsChooser || changingProfile)
            .zIndex(0)
            Group {
                if !isLoadingProfiles {
                    ProfileChooserView(isSwitching: hasEnteredApp,
                        onCancel: hasEnteredApp ? { profiles.cancelSwitch() } : nil,
                        onSelect: selectProfile, resetToken: chooserReset)
                        .opacity(showsChooser ? 1 : 0)
                        .scaleEffect(!reduceMotion && !showsChooser ? 1.025 : 1)
                }
            }
            .allowsHitTesting(!isLoadingProfiles && profiles.requiresSelection && showsChooser && !changingProfile)
            .accessibilityHidden(isLoadingProfiles || !profiles.requiresSelection || !showsChooser || changingProfile)
            .zIndex(1)
            if isLoadingProfiles {
                loadingProfiles
                    .zIndex(2)
            }
        }
        .preferredColorScheme(showsChooser ? .dark : settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
        .task(id: account.identity?.uid) { await profiles.setAccount(account.identity); completeSignIn() }
        .onChange(of: account.homeIntent) { _, _ in completeSignIn() }
        .onChange(of: profiles.syncStatus) { _, _ in completeSignIn() }
        .onChange(of: profiles.requiresSelection, initial: true) { _, choosing in
            if choosing { sportsPlayback.close() }
            if choosing && returningFromSignIn { return }
            guard initialized else {
                initialized = true
                showsChooser = choosing
                return
            }
            guard !changingProfile else { return }
            changingProfile = true
            withAnimation(handoffAnimation, completionCriteria: .logicallyComplete) {
                showsChooser = choosing
            } completion: { finishProfileTransition() }
        }
    }

    private func completeSignIn() {
        guard let intent = account.homeIntent, account.identity?.uid == intent.uid,
              profiles.finishSignIn(uid: intent.uid) else { return }
        homeRevision += 1
        account.consumeHomeIntent(intent.id)
    }

    private func selectProfile(_ id: UUID) {
        guard !changingProfile, profiles.canEditProfiles,
              profiles.profiles.contains(where: { $0.id == id }) else { return }
        changingProfile = true
        sportsPlayback.close()
        if showsChooser {
            // Mount the selected viewer's root behind the still-visible chooser
            // before fading. Replacing its identity during the fade cuts it short.
            profiles.select(id)
            let context = profiles.contextID
            Task { @MainActor in
                await Task.yield()
                guard profiles.contextID == context, !profiles.requiresSelection else {
                    finishProfileTransition()
                    return
                }
                withAnimation(handoffAnimation, completionCriteria: .logicallyComplete) {
                    showsChooser = false
                } completion: { finishProfileTransition() }
            }
        } else {
            // A quick switch has no full chooser. Fade out the old viewer before
            // changing its stores/theme, then reveal the new root as one surface.
            let owner = profiles.ownerUID
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), completionCriteria: .logicallyComplete) {
                rootDimmed = true
            } completion: {
                guard profiles.ownerUID == owner, profiles.canEditProfiles,
                      profiles.profiles.contains(where: { $0.id == id }) else {
                    finishProfileTransition()
                    return
                }
                profiles.select(id)
                let context = profiles.contextID
                Task { @MainActor in
                    await Task.yield()
                    guard profiles.ownerUID == owner, profiles.contextID == context,
                          !profiles.requiresSelection else {
                        finishProfileTransition()
                        return
                    }
                    withAnimation(handoffAnimation, completionCriteria: .logicallyComplete) {
                        rootDimmed = false
                    } completion: { finishProfileTransition() }
                }
            }
        }
    }

    private func finishProfileTransition() {
        rootDimmed = false
        // Account restoration, sign-out or deletion can request the chooser
        // during a handoff. Reconcile to the store before unlocking either UI.
        let choosing = profiles.requiresSelection
        guard showsChooser == choosing else {
            withAnimation(handoffAnimation, completionCriteria: .logicallyComplete) {
                showsChooser = choosing
            } completion: { finishProfileTransition() }
            return
        }
        changingProfile = false
        if !choosing { chooserReset += 1 }
    }

    private var loadingProfiles: some View {
        VStack(spacing: 18) {
            Image("streamify-logo").resizable().scaledToFit().frame(width: 64, height: 64)
            if !account.isResolved || profiles.ownerUID != account.identity?.uid || profiles.syncStatus == .loading || profiles.syncStatus == .syncing {
                ProgressView("Opening your profiles…").tint(AppTheme.foreground)
            } else {
                Text(profiles.syncStatus.title).font(.subheadline).multilineTextAlignment(.center)
                Button("Try again") { Task { await profiles.retrySync() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if account.isResolved, account.identity != nil {
                Button("Use guest profiles") { Task { await account.signOut() } }
                    .buttonStyle(SecondaryButtonStyle()).disabled(account.isWorking)
                if let error = account.error { Text(error).font(.caption).foregroundStyle(AppTheme.muted) }
            }
        }.padding(24).frame(maxWidth: 360)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(AppTheme.foreground).background(AppTheme.canvas.ignoresSafeArea())
    }
}

enum AppTab: String, CaseIterable {
    case home, sports, search, library
    var title: String {
        switch self { case .home: "Home"; case .sports: "Sports"; case .search: "Search"; case .library: "My list" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .sports: "globe"; case .search: "magnifyingglass"; case .library: "person.crop.square" }
    }
}

struct RootView: View {
    let onSelectProfile: (UUID) -> Void
    private enum LibraryDestination: Hashable { case downloads }
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var sportsPlayback: SportsPlaybackSession
    @EnvironmentObject private var quickActions: AppQuickActionRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    @State private var settingsOpen = false
    @State private var accountOpen = false
    @State private var downloadsOpen = false
    @State private var catalogSearchOpen = false
    @State private var catalogSearchSourceID = "root-search-home"
    @Namespace private var searchTransition
    @State private var sportsSearchRequest = 0
    @State private var keyboardVisible = false
    @State private var visibleRootPages = Set(AppTab.allCases)
    @State private var navigationRevision = 0
    @State private var libraryPath: [LibraryDestination] = []
    @State private var quickActionRequest: AppQuickActionRouter.Request?
    @State private var quickActionLoading = false
    @State private var quickActionError: String?

    private var activeDownloads: [DownloadItem] { downloads.items.filter { $0.status == .downloading } }
    private var downloadProgress: Double? {
        DownloadToolbarProgress.average(in: downloads.items)
    }
    private var downloadActivityValue: String {
        guard !activeDownloads.isEmpty else { return "No active downloads" }
        let count = activeDownloads.count
        return "\(count) download\(count == 1 ? "" : "s") in progress, " +
            (downloadProgress.map { "\(Int($0 * 100)) percent" } ?? "total size unknown")
    }

    private var rootSelection: Binding<AppTab> {
        Binding(get: { tab }, set: { value in
            if tab != value { quickActionRequest = nil; quickActionLoading = false; quickActionError = nil }
            visibleRootPages.insert(value)
            tab = value
        })
    }

    private var bottomBarContainerEdges: Edge.Set {
        if #available(iOS 26.0, *) { return .bottom }
        return []
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: rootSelection) {
                ForEach(AppTab.allCases, id: \.self) { page in
                    rootStack(page).id(navigationRevision).tag(page)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
            // The pill overlays the scroll viewport; only scroll content gets
            // bottom padding. Reserving a sibling footer creates a solid shelf.
            if !keyboardVisible && visibleRootPages.contains(tab) && (tab != .library || libraryPath.isEmpty) {
                LiquidGlassBottomBar(selection: rootSelection, onSelectProfile: onSelectProfile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // UIKit already keeps the glass pill clear of the home indicator.
        // Align its container to the screen edge rather than adding SwiftUI's
        // bottom safe area on top of UIKit's own inset.
        .ignoresSafeArea(.container, edges: bottomBarContainerEdges)
        // One backdrop also fills the status bar and home-indicator area.
        .background { StreamifyRootBackdrop() }
        .sheet(isPresented: $settingsOpen) {
            NavigationStack { SettingsView() }
                .preferredColorScheme(settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
        }
        .sheet(isPresented: $accountOpen) { NavigationStack { AccountView() } }
        .sheet(isPresented: $downloadsOpen) { NavigationStack { DownloadsView() } }
        .task(id: "\(profiles.contextID)|\(settings.liveTeamAlerts)|\(library.followedTeams.sorted().joined(separator: ","))|\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            SportsLiveAlerts.shared.configure(teams: Set(library.followedTeams), enabled: settings.liveTeamAlerts)
        }
        .streamifySearchPresentation(isPresented: $catalogSearchOpen, sourceID: catalogSearchSourceID, in: searchTransition) {
            CatalogSearchDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .task(id: "\(quickActions.pending?.id.uuidString ?? "none")-\(scenePhase == .active)") {
            guard scenePhase == .active, let request = quickActions.takePending() else { return }
            navigate(request)
        }
        .task(id: quickActionRequest?.id) {
            guard let request = quickActionRequest,
                  case .watchSports(let league, let eventID) = request.destination else { return }
            await watchGame(league: league, eventID: eventID, request: request)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { quickActionRequest = nil; quickActionLoading = false }
        }
        .overlay {
            if quickActionLoading {
                PlaybackConnectingView(title: "Opening game", compact: true)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false).accessibilityIdentifier("opening-widget-game")
            }
        }
        .alert("Stream unavailable", isPresented: Binding(get: { quickActionError != nil }, set: { if !$0 { quickActionError = nil } })) {
            Button("OK") { quickActionError = nil }
        } message: { Text(quickActionError ?? "Try another live game in Sports.") }
    }

    @ViewBuilder
    private func rootStack(_ page: AppTab) -> some View {
        Group {
            if page == .library {
                NavigationStack(path: $libraryPath) {
                    rootPage(.library) {
                        LibraryView(favoritesRequest: quickActionRequest?.destination == .favorites ? quickActionRequest?.id : nil)
                    }
                    .navigationDestination(for: LibraryDestination.self) { _ in
                        DownloadsView().toolbar(.visible, for: .navigationBar)
                    }
                }
            } else {
                NavigationStack {
                    switch page {
                    case .home: rootPage(.home) { HomeView(openSettings: { settingsOpen = true }, openSports: { tab = .sports }) }
                    case .sports: rootPage(.sports) {
                        SportsView(searchRequest: sportsSearchRequest, searchNamespace: searchTransition, searchSourceID: "root-search-sports")
                    }
                    case .search: rootPage(.search) { BrowseView() }
                    case .library: EmptyView()
                    }
                }
            }
        }.environment(\.scenePhase, page == tab ? scenePhase : .inactive)
    }

    private func navigate(_ request: AppQuickActionRouter.Request) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        settingsOpen = false; accountOpen = false; downloadsOpen = false; catalogSearchOpen = false
        quickActionLoading = false; quickActionError = nil; keyboardVisible = false
        sportsSearchRequest = 0
        libraryPath = []
        navigationRevision &+= 1
        // A deliberate Home Screen destination closes an expanded overlay. An
        // actual system PiP session remains owned by the app and keeps playing.
        if sportsPlayback.isExpanded { sportsPlayback.close() }
        switch request.destination {
        case .downloads: tab = .library; libraryPath = [.downloads]
        case .favorites: tab = .library
        case .sports, .watchSports: tab = .sports
        }
        visibleRootPages.insert(tab)
        quickActionRequest = request
    }

    private func watchGame(league: SportsLeague, eventID: String, request: AppQuickActionRouter.Request) async {
        quickActionLoading = true
        defer { if quickActionRequest?.id == request.id { quickActionLoading = false } }
        do {
            let service = SportsService(backend: settings.apiBase)
            let game = try await service.game(league: league, eventID: eventID)
            try Task.checkCancellation()
            let sources = try await service.streams(game)
            try Task.checkCancellation()
            guard quickActionRequest?.id == request.id, scenePhase == .active, tab == .sports,
                  !settingsOpen, !accountOpen, !downloadsOpen, !catalogSearchOpen else { return }
            guard let first = sportsPlayback.preferredSource(in: sources) else {
                quickActionError = game.isFinal ? "This game has finished. Choose a live game in Sports."
                    : "No stream is available for this game right now. Try its Game Center or another live game in Sports."
                return
            }
            sportsPlayback.play(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: first.url, sources: sources, game: game)
        } catch is CancellationError { }
        catch {
            if !Task.isCancelled, quickActionRequest?.id == request.id {
                quickActionError = "The game could not be opened. \(error.localizedDescription)"
            }
        }
    }

    private func rootPage<Content: View>(_ page: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background { RootTabScrollToTop(tab: page) }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header(page) }
            .background { StreamifyRootBackdrop() }
            .onAppear { visibleRootPages.insert(page) }
            .onDisappear { visibleRootPages.remove(page) }
    }

    private func header(_ page: AppTab) -> some View {
        HStack(spacing: 0) {
            Image("streamify-logo").resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            Text(page.title).font(.system(size: 24, weight: .bold)).lineLimit(1)
                .padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("root-title-\(page.rawValue)")
            if sportsPlayback.isPiPActive {
                Button { sportsPlayback.expand() } label: { Image(systemName: "pip.exit").frame(width: 44, height: 44) }
                    .accessibilityLabel("Return to player").accessibilityIdentifier("sports-pip-restore")
            }
            Button {
                if page == .sports { sportsSearchRequest += 1 }
                else {
                    catalogSearchSourceID = "root-search-\(page.rawValue)"
                    catalogSearchOpen = true
                }
            } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                .accessibilityLabel("Search")
                .accessibilityIdentifier(page == .sports ? "focus-sports-search" : "open-catalog-search")
                .streamifySearchSource("root-search-\(page.rawValue)", in: searchTransition)
            Button { downloadsOpen = true } label: {
                ZStack {
                    if activeDownloads.isEmpty {
                        Image(systemName: "arrow.down.to.line")
                    } else {
                        // An empty ring waits for real progress; it never
                        // invents a percentage or turns into a rotating badge.
                        DownloadActivityIndicator(progress: downloadProgress ?? 0, size: 28,
                                                  tint: AppTheme.foreground, animated: false)
                        Image(systemName: "arrow.down").font(.system(size: 13, weight: .semibold))
                    }
                }.frame(width: 44, height: 44)
            }.accessibilityLabel("Downloads").accessibilityValue(downloadActivityValue).accessibilityIdentifier("open-downloads")
            Menu {
                Button("Switch profiles", systemImage: "person.2") { profiles.showChooser() }
                Button("Account", systemImage: "person.crop.circle") { accountOpen = true }
                Button("Settings", systemImage: "gearshape") { settingsOpen = true }
            } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }
                .accessibilityLabel("More options")
        }
        .font(.system(size: 23)).buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.foreground)
        .padding(.leading, 16).padding(.trailing, 8).frame(height: 60)
        .background(AppTheme.rootTopTint.ignoresSafeArea(edges: .top))
    }
}
