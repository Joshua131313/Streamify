import SwiftUI

@main
@MainActor
struct StreamifyApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var library: LibraryStore
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var sportsPlayback = SportsPlaybackSession()

    init() {
        #if DEBUG
        if PreviewFixtures.enabled { PreviewFixtures.install() }
        _settings = StateObject(wrappedValue: SettingsStore(defaults: PreviewFixtures.enabled ? PreviewFixtures.defaults : .standard))
        _library = StateObject(wrappedValue: LibraryStore(defaults: PreviewFixtures.enabled ? PreviewFixtures.defaults : .standard))
        #else
        _settings = StateObject(wrappedValue: SettingsStore())
        _library = StateObject(wrappedValue: LibraryStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .buttonStyle(HapticAutomaticButtonStyle())
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(sportsPlayback)
                .background { SportsPlaybackHost(session: sportsPlayback).frame(width: 0, height: 0) }
                .tint(AppTheme.foreground)
                .preferredColorScheme(settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
                .onAppear {
                    #if DEBUG
                    if PreviewFixtures.enabled {
                        PreviewFixtures.seedLibrary(library)
                        PreviewFixtures.seedDownloads(downloads)
                    }
                    #endif
                }
        }
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
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var sportsPlayback: SportsPlaybackSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    @State private var settingsOpen = false
    @State private var accountOpen = false
    @State private var downloadsOpen = false
    @State private var catalogSearchOpen = false
    @State private var sportsSearchRequest = 0
    @State private var keyboardVisible = false
    @State private var visibleRootPages = Set(AppTab.allCases)

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
            visibleRootPages.insert(value)
            tab = value
        })
    }

    var body: some View {
        TabView(selection: rootSelection) {
            ForEach(AppTab.allCases, id: \.self) { page in
                rootStack(page).tag(page)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible && visibleRootPages.contains(tab) {
                FloatingNavigation(selection: rootSelection)
            }
        }
        // One backdrop also fills the status bar and home-indicator area.
        .background { StreamifyRootBackdrop() }
        .sheet(isPresented: $settingsOpen) {
            NavigationStack { SettingsView() }
                .preferredColorScheme(settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
        }
        .sheet(isPresented: $accountOpen) { NavigationStack { AccountView() } }
        .sheet(isPresented: $downloadsOpen) { NavigationStack { DownloadsView() } }
        .sheet(isPresented: $catalogSearchOpen) { CatalogSearchDialog() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    private func rootStack(_ page: AppTab) -> some View {
        NavigationStack {
            switch page {
            case .home: rootPage(.home) { HomeView(openSettings: { settingsOpen = true }, openSports: { tab = .sports }) }
            case .sports: rootPage(.sports) { SportsView(searchRequest: sportsSearchRequest) }
            case .search: rootPage(.search) { BrowseView() }
            case .library: rootPage(.library) { LibraryView() }
            }
        }.environment(\.scenePhase, page == tab ? scenePhase : .inactive)
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
                else { catalogSearchOpen = true }
            } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                .accessibilityLabel("Search")
                .accessibilityIdentifier(page == .sports ? "focus-sports-search" : "open-catalog-search")
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
                                Image(systemName: "person.fill").font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white).frame(width: 23, height: 23)
                                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 7))
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
