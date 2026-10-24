import SwiftUI

@main
@MainActor
struct StreamifyApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var library: LibraryStore
    @StateObject private var downloads = DownloadStore.shared

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
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(downloads)
                .tint(AppTheme.accent)
                .preferredColorScheme(settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
                .onAppear {
                    #if DEBUG
                    if PreviewFixtures.enabled { PreviewFixtures.seedLibrary(library) }
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
    @State private var tab: AppTab = .home
    @State private var settingsOpen = false
    @State private var accountOpen = false
    @State private var downloadsOpen = false
    @State private var sportsSearchRequest = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { rootPage(.home) { HomeView(openSettings: { settingsOpen = true }, openSports: { tab = .sports }) } }.tag(AppTab.home)
            NavigationStack { rootPage(.sports) { SportsView(searchRequest: sportsSearchRequest) } }.tag(AppTab.sports)
            NavigationStack { rootPage(.search) { BrowseView() } }.tag(AppTab.search)
            NavigationStack { rootPage(.library) { LibraryView() } }.tag(AppTab.library)
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $settingsOpen) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $accountOpen) { NavigationStack { AccountView() } }
        .sheet(isPresented: $downloadsOpen) { NavigationStack { DownloadsView() } }
    }

    private func rootPage<Content: View>(_ page: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header(page) }
            .safeAreaInset(edge: .bottom, spacing: 0) { FloatingNavigation(selection: $tab) }
            .background { StreamifyRootBackdrop() }
    }

    private func header(_ page: AppTab) -> some View {
        HStack(spacing: 0) {
            Image("streamify-logo").resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            Text(page.title).font(.system(size: 24, weight: .bold)).lineLimit(1)
                .padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            Button {
                if page == .sports { sportsSearchRequest += 1 }
                else { tab = .search }
            } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                .accessibilityLabel("Search")
                .accessibilityIdentifier(page == .sports ? "focus-sports-search" : "open-catalog-search")
            Button { downloadsOpen = true } label: {
                Image(systemName: "arrow.down.to.line").frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if downloads.items.contains(where: { $0.status == .downloading }) {
                            Circle().fill(AppTheme.accent).frame(width: 7, height: 7).padding(8)
                        }
                    }
            }.accessibilityLabel("Downloads").accessibilityIdentifier("open-downloads")
            Menu {
                Button("Account", systemImage: "person.crop.circle") { accountOpen = true }
                Button("Settings", systemImage: "gearshape") { settingsOpen = true }
            } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }
                .accessibilityLabel("More options")
        }
        .font(.system(size: 23)).buttonStyle(.plain).foregroundStyle(AppTheme.foreground)
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 60)
    }
}

private struct FloatingNavigation: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection = tab }
                } label: {
                    VStack(spacing: 2) {
                        if tab == .library {
                            Image(systemName: "person.fill").font(.system(size: 18))
                                .foregroundStyle(.white).frame(width: 24, height: 24)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 7))
                        } else {
                            Image(systemName: tab.symbol).font(.system(size: 24))
                                .foregroundStyle(AppTheme.foreground.opacity(tab == selection ? 1 : 0.5))
                        }
                        Text(tab.title).font(.system(size: 10, weight: tab == selection ? .semibold : .medium))
                            .foregroundStyle(AppTheme.foreground.opacity(tab == selection ? 1 : 0.5))
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 54)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? [.isSelected] : [])
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2).frame(maxWidth: 400)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 29))
        .overlay { RoundedRectangle(cornerRadius: 29).stroke(AppTheme.border, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding(.horizontal, 40).padding(.top, 8).padding(.bottom, 6)
    }
}
