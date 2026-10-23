import SwiftUI

@main
struct StreamifyApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var downloads = DownloadStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(downloads)
                .tint(AppTheme.accent)
                .preferredColorScheme(settings.appearance == "System" ? nil : settings.appearance == "Light" ? .light : .dark)
        }
    }
}

enum AppTab: String, CaseIterable {
    case home, sports, search, library
    var title: String {
        switch self { case .home: "Home"; case .sports: "Sports"; case .search: "Search"; case .library: "My list" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .sports: "basketball"; case .search: "magnifyingglass"; case .library: "person.crop.square" }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var settingsOpen = false
    @State private var accountOpen = false
    @State private var downloadsOpen = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { rootPage(.home) { HomeView(openSettings: { settingsOpen = true }, openSports: { tab = .sports }) } }.tag(AppTab.home)
            NavigationStack { rootPage(.sports) { SportsView() } }.tag(AppTab.sports)
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
            .background(AppTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.canvas.opacity(0.95), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        Image("streamify-logo").resizable().scaledToFit().frame(width: 26, height: 30).accessibilityHidden(true)
                        Text(page.title).font(.title2.bold())
                    }.accessibilityAddTraits(.isHeader)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if page != .search && page != .sports {
                        Button { tab = .search } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search")
                    }
                    Menu {
                        Button("My list", systemImage: "bookmark") { tab = .library }
                        Button("Account", systemImage: "person.crop.circle") { accountOpen = true }
                        Button("Downloads", systemImage: "arrow.down.circle") { downloadsOpen = true }
                        Button("Settings", systemImage: "gearshape") { settingsOpen = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }.accessibilityLabel("More options")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { FloatingNavigation(selection: $tab) }
    }
}

private struct FloatingNavigation: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection = tab }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab == selection && tab != .search ? tab.symbol + ".fill" : tab.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tab == selection ? AppTheme.accent : AppTheme.muted)
                        Text(tab.title).font(.caption2.weight(.semibold))
                            .foregroundStyle(tab == selection ? Color.primary : AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 58)
                    .background(tab == selection ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 25))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? [.isSelected] : [])
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(AppTheme.border, lineWidth: 1) }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
    }
}
