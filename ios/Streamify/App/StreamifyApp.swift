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

    init() {
        SportsChatBootstrap.configure()
        _account = StateObject(wrappedValue: AccountSession())
        #if DEBUG
        if PreviewFixtures.enabled { PreviewFixtures.install() }
        let profileStore = ProfileStore(defaults: PreviewFixtures.enabled ? PreviewFixtures.defaults : .standard,
            chooseOnLaunch: !PreviewFixtures.enabled || ProcessInfo.processInfo.arguments.contains("--ui-profile-chooser"))
        if PreviewFixtures.enabled { PreviewFixtures.seedLibrary(profileStore.library) }
        _profiles = StateObject(wrappedValue: profileStore)
        if PreviewFixtures.enabled {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--ui-quick-action"), arguments.indices.contains(index + 1),
               let action = AppQuickAction.allCases.first(where: { $0.rawValue.split(separator: ".").last.map(String.init) == arguments[index + 1] }) {
                AppQuickActionRouter.shared.enqueue(action.destination)
            }
        }
        #else
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
                .tint(AppTheme.foreground)
                .onOpenURL { quickActions.enqueue(url: $0) }
                .onAppear {
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
    @State private var hasEnteredApp = false

    private var isLoadingProfiles: Bool {
        !account.isResolved || profiles.ownerUID != account.identity?.uid || !profiles.canEditProfiles
    }
    private var profileTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.025))
    }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            Group {
                if !isLoadingProfiles && !profiles.requiresSelection {
                    RootView().id(profiles.contextID)
                        .onAppear { hasEnteredApp = true }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .allowsHitTesting(!isLoadingProfiles && !profiles.requiresSelection)
            .accessibilityHidden(isLoadingProfiles || profiles.requiresSelection)
            .zIndex(0)
            Group {
                if !isLoadingProfiles && profiles.requiresSelection {
                    ProfileChooserView(isSwitching: hasEnteredApp,
                        onCancel: hasEnteredApp ? { profiles.cancelSwitch() } : nil)
                        .transition(profileTransition)
                }
            }
            .allowsHitTesting(!isLoadingProfiles && profiles.requiresSelection)
            .accessibilityHidden(isLoadingProfiles || !profiles.requiresSelection)
            .zIndex(1)
            if isLoadingProfiles {
                loadingProfiles
                    .zIndex(2)
            }
        }
        .animation(isLoadingProfiles ? nil : .easeInOut(duration: reduceMotion ? 0.12 : 0.3), value: profiles.requiresSelection)
        .preferredColorScheme(profiles.requiresSelection ? .dark : settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
        .task(id: account.identity?.uid) { await profiles.setAccount(account.identity) }
        .onChange(of: profiles.requiresSelection) { _, choosing in
            if choosing { sportsPlayback.close() }
        }
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
    private enum LibraryDestination: Hashable { case downloads }
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var profiles: ProfileStore
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
        let active = activeDownloads
        guard !active.isEmpty, active.allSatisfy({ $0.expectedBytes > 0 }) else { return nil }
        let expected = active.reduce(0.0) { $0 + Double($1.expectedBytes) }
        let written = active.reduce(0.0) { $0 + Double(min(max(0, $1.bytesWritten), $1.expectedBytes)) }
        guard expected.isFinite, written.isFinite, expected > 0 else { return nil }
        return min(1, max(0, written / expected))
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

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: rootSelection) {
                ForEach(AppTab.allCases, id: \.self) { page in
                    rootStack(page).id(navigationRevision).tag(page)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep the footer outside UIKit's paging surface. Its intrinsic
            // height reserves the same space without giving a carousel's
            // native view a hit region underneath these navigation buttons.
            if !keyboardVisible && visibleRootPages.contains(tab) && (tab != .library || libraryPath.isEmpty) {
                FloatingNavigation(selection: rootSelection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One backdrop also fills the status bar and home-indicator area.
        .background { StreamifyRootBackdrop() }
        .sheet(isPresented: $settingsOpen) {
            NavigationStack { SettingsView() }
                .preferredColorScheme(settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
        }
        .sheet(isPresented: $accountOpen) { NavigationStack { AccountView() } }
        .sheet(isPresented: $downloadsOpen) { NavigationStack { DownloadsView() } }
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
                ProgressView("Opening game…").padding(24).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
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
            guard let first = sources.first else {
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
                Image(systemName: "arrow.down.to.line").frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if !activeDownloads.isEmpty {
                            DownloadActivityIndicator(progress: downloadProgress, size: 12, tint: AppTheme.accent)
                                .padding(5)
                        }
                    }
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

private struct FloatingNavigation: View {
    @Binding var selection: AppTab
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectedTabAnimation
    @State private var selectionFeedback = 0
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9.5

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    guard !selected else { return }
                    selectionFeedback += 1
                    selection = tab
                } label: {
                    VStack(spacing: 1) {
                        ZStack {
                            if tab == .library {
                                ProfileAvatarView(avatar: profiles.activeProfile?.avatar ?? .crimson, size: 23)
                            } else {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 21, weight: .light))
                                    .foregroundStyle(AppTheme.foreground.opacity(selected ? 1 : 0.55))
                            }
                        }
                        .frame(width: 24, height: 24)
                        .scaleEffect(selected && !reduceMotion ? 1.06 : 1)
                        .accessibilityHidden(true)
                        Text(tab.title).font(.system(size: labelSize, weight: selected ? .semibold : .medium))
                            .foregroundStyle(AppTheme.foreground.opacity(selected ? 1 : 0.55))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .scaleEffect(selected && !reduceMotion ? 1.02 : 1)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 50)
                    .background {
                        if selected {
                            Capsule().fill(AppTheme.foreground.opacity(colorScheme == .dark ? 0.12 : 0.08))
                                .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(0.06), lineWidth: 0.5) }
                                .matchedGeometryEffect(id: "selected-tab", in: selectedTabAnimation)
                                .padding(.horizontal, 2)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(tab == .library ? "Profile: \(profiles.activeProfile?.name ?? "My profile"), \(profiles.activeProfile?.avatar.title ?? "Crimson") avatar" : "")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(3).frame(maxWidth: 400)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay { Capsule().fill(AppTheme.canvas.opacity(colorScheme == .dark ? 0.3 : 0.55)) }
        }
        .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(colorScheme == .dark ? 0.14 : 0.1), lineWidth: 0.7) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 12, y: 5)
        .animation(selectionAnimation, value: selection)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .padding(.horizontal, 50).padding(.top, 4)
    }
}
