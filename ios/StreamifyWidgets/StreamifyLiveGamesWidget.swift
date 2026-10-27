import SwiftUI
import WidgetKit
import UIKit
import AppIntents

/// Widget button intents trigger a new timeline when they finish. The provider
/// uses an ephemeral session, so this fetches scores rather than reopening the app.
struct RefreshLiveGamesIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh live scores"
    static var description = IntentDescription("Check for the latest Streamify game scores.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: SportsWidgetPolicy.kind)
        return .result()
    }
}

@main
struct StreamifyWidgetsBundle: WidgetBundle {
    var body: some Widget { StreamifyLiveGamesWidget(); TrackedGameLiveActivity() }
}

struct StreamifyLiveGamesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SportsWidgetPolicy.kind, provider: LiveGamesProvider()) { entry in
            LiveGamesWidgetView(entry: entry)
                .containerBackground(for: .widget) { LiveGamesBackground() }
        }
        .configurationDisplayName("Streamify Live Games")
        .description("Live scores and quick links to watch. Updates are managed by iOS.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct LiveGamesBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
            ? [Color(red: 0.19, green: 0.15, blue: 0.21), Color(red: 0.043, green: 0.051, blue: 0.063)]
            : [Color(red: 0.93, green: 0.90, blue: 0.95), Color(red: 0.98, green: 0.98, blue: 0.99)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct LiveGamesWidgetView: View {
    let entry: LiveGamesEntry
    @Environment(\.widgetFamily) private var family
    private var limit: Int { family == .systemLarge ? 4 : family == .systemMedium ? 2 : 1 }
    private var destination: URL {
        family == .systemSmall ? entry.games.first.flatMap(SportsWidgetPolicy.watchURL) ?? SportsWidgetPolicy.sportsURL : SportsWidgetPolicy.sportsURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : family == .systemSmall ? 5 : 4) {
            header
            if entry.games.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if family == .systemSmall, let game = entry.games.first {
                smallGame(game)
            } else {
                ForEach(Array(entry.games.prefix(limit))) { game in
                    if let url = SportsWidgetPolicy.watchURL(for: game) {
                        Link(destination: url) { gameRow(game) }.buttonStyle(.plain)
                    }
                }
                if family == .systemLarge { Spacer(minLength: 0) }
            }
            footer
        }.padding(family == .systemLarge ? 14 : 12)
            .widgetURL(destination)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let image = WidgetLogoImages.brand {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true)
            }
            Text(family == .systemSmall ? "Live games" : "Streamify").font(.system(size: 13, weight: .bold)).lineLimit(1)
            Spacer(minLength: 2)
            if !entry.games.isEmpty && family != .systemSmall {
                Circle().fill(Color(red: 0.96, green: 0.23, blue: 0.30)).frame(width: 4, height: 4)
                Text("\(entry.liveCount) live").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Button(intent: RefreshLiveGamesIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Refresh live scores")
                .accessibilityHint("Fetches updated scores without opening Streamify")
                .accessibilityIdentifier("widget-refresh-scores")
                .invalidatableContent()
        }
    }

    private func smallGame(_ game: SportsGame) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(game.league.title) · \(game.status)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            teamLine(game.away, logoSize: 16, scoreSize: 17)
            teamLine(game.home, logoSize: 16, scoreSize: 17)
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.system(size: 8))
                Text("Watch").font(.system(size: 10, weight: .semibold))
            }.padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
        }.frame(maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Watch \(game.away.name) at \(game.home.name), \(game.away.score) to \(game.home.score), \(game.status)")
    }

    private func gameRow(_ game: SportsGame) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: family == .systemMedium ? 1 : 3) {
                teamLine(game.away, logoSize: family == .systemMedium ? 13 : 16, scoreSize: family == .systemMedium ? 13 : 15)
                teamLine(game.home, logoSize: family == .systemMedium ? 13 : 16, scoreSize: family == .systemMedium ? 13 : 15)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: family == .systemMedium ? 1 : 4) {
                Text(game.league.title).font(.system(size: family == .systemMedium ? 8 : 9, weight: .bold)).foregroundStyle(.secondary)
                Text(game.status).font(.system(size: family == .systemMedium ? 8 : 9)).foregroundStyle(.secondary).lineLimit(1)
                Label("Watch", systemImage: "play.fill").font(.system(size: family == .systemMedium ? 9 : 10, weight: .semibold))
            }.frame(width: family == .systemLarge ? 95 : 90, alignment: .trailing)
        }.padding(.horizontal, 9).padding(.vertical, family == .systemLarge ? 7 : 2)
            .frame(height: family == .systemMedium ? 40 : nil)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Watch \(game.league.title), \(game.away.name) at \(game.home.name), \(game.away.score) to \(game.home.score), \(game.status)")
    }

    private func teamLine(_ team: SportsTeam, logoSize: CGFloat, scoreSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            if let data = entry.logos[team.logo], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: logoSize, height: logoSize).accessibilityHidden(true)
            } else { Image(systemName: "sportscourt").font(.system(size: logoSize - 5)).frame(width: logoSize, height: logoSize).foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(team.abbreviation.isEmpty ? team.name : team.abbreviation).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 2)
            Text(team.score.isEmpty ? "–" : team.score).font(.system(size: scoreSize, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.state == .unavailable ? "wifi.slash" : "sportscourt")
                .font(.system(size: family == .systemSmall ? 19 : 24, weight: .light)).foregroundStyle(.secondary)
            Text(emptyTitle).font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold))
            Text(emptyMessage).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
        }
    }
    private var emptyTitle: String {
        switch entry.state {
        case .loading: return "Your live games"
        case .unavailable: return "Scores unavailable"
        case .partial: return "Some scores unavailable"
        case .stale: return "Time for an update"
        case .current: return "No live games"
        }
    }
    private var emptyMessage: String {
        switch entry.state {
        case .loading: return "Live scores and Watch links appear here when games are on."
        case .unavailable, .partial: return "Open Sports for the latest available schedule."
        case .stale: return "Open Streamify to see the latest games and streams."
        case .current: return "See today’s schedule in Streamify."
        }
    }
    private var footer: some View {
        HStack(spacing: 3) {
            if entry.state == .partial { Text("Partial ·").font(.system(size: 8)) }
            if let updated = entry.updatedAt {
                Text(entry.state == .stale ? "Last checked" : "Updated").font(.system(size: 8))
                Text(updated, style: .time).font(.system(size: 8)).monospacedDigit()
            } else { Text("Open Sports").font(.system(size: 9, weight: .medium)) }
            Spacer(minLength: 0)
            if entry.liveCount > limit { Text("+\(entry.liveCount - limit) more").font(.system(size: 8, weight: .medium)) }
        }.foregroundStyle(.secondary).lineLimit(1)
    }
}
