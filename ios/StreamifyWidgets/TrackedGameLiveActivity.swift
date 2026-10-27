import SwiftUI
import WidgetKit
import ActivityKit
import UIKit

/// Logos are bundled: a Live Activity cannot fetch images.
struct TrackedGameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SportsTrackedGameAttributes.self) { context in
            TrackedGameScoreCard(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.watchURL)
        } dynamicIsland: { context in
            DynamicIsland(expanded: {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) { teamLogo(context.attributes, home: false, size: 24); Text(score(context.state.awayScore)).bold().monospacedDigit() }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 5) { Text(score(context.state.homeScore)).bold().monospacedDigit(); teamLogo(context.attributes, home: true, size: 24) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.isStale ? "Last score received" : context.state.situation ?? context.state.status).font(.caption).lineLimit(1)
                        Spacer()
                        Link(destination: context.attributes.watchURL) { Label("Watch", systemImage: "play.fill").font(.caption.weight(.semibold)) }
                    }
                }
            }, compactLeading: { HStack(spacing: 3) { teamLogo(context.attributes, home: false, size: 18); Text(score(context.state.awayScore)).font(.caption2.monospacedDigit()) } },
              compactTrailing: { HStack(spacing: 3) { Text(score(context.state.homeScore)).font(.caption2.monospacedDigit()); teamLogo(context.attributes, home: true, size: 18) } },
              minimal: { Image(systemName: "sportscourt") }).widgetURL(context.attributes.watchURL)
        }
    }
    private func score(_ value: String) -> String { value.isEmpty ? "–" : value }
}

struct TrackedGameScoreCard: View {
    let attributes: SportsTrackedGameAttributes
    let state: SportsTrackedGameAttributes.ContentState
    var stale = false
    private var pregame: Bool { state.pregame == true }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                team(home: false)
                Text(score(state.awayScore)).font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 34).contentTransition(.numericText())
                VStack(spacing: 4) {
                    Text(state.final ? "FINAL" : pregame ? "PREGAME" : "LIVE").font(.system(size: 10, weight: .bold)).tracking(0.5)
                    if stale {
                        Text("Updated").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                        Text(state.updatedAt, style: .time).font(.system(size: 10).monospacedDigit())
                    } else {
                        Text(pregame ? "Begins soon" : state.status).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                        if let situation = state.situation, !situation.isEmpty {
                            Text(situation).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                        }
                    }
                }.frame(maxWidth: .infinity)
                Text(score(state.homeScore)).font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 34).contentTransition(.numericText())
                team(home: true)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            Rectangle().fill(.white.opacity(0.09)).frame(height: 0.5)
            HStack(spacing: 8) {
                if let logo = UIImage(named: "league-\(attributes.league)") {
                    Image(uiImage: logo).resizable().scaledToFit().frame(width: 31, height: 23).accessibilityLabel(attributes.league.uppercased())
                } else { Text(attributes.league == "college-football" ? "CFB" : attributes.league.uppercased()).font(.caption2.bold()) }
                Spacer(minLength: 0)
                if let venue = attributes.venue, !venue.isEmpty { Text(venue).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                else { Text("Streamify").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)) }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.system(size: 20)).accessibilityLabel("Watch game")
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }.foregroundStyle(.white).background(.black)
    }
    private func score(_ value: String) -> String { pregame || value.isEmpty ? "–" : value }
    private func team(home: Bool) -> some View {
        VStack(spacing: 4) {
            teamLogo(attributes, home: home, size: 40)
            Text((home ? attributes.homeName : attributes.awayName) ?? (home ? attributes.home : attributes.away))
                .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            let record = (home ? attributes.homeRecord : attributes.awayRecord) ?? ""
            if !record.isEmpty { Text(record).font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)) }
        }.frame(width: 64)
    }
}

@ViewBuilder
private func teamLogo(_ attributes: SportsTrackedGameAttributes, home: Bool, size: CGFloat) -> some View {
    let id = home ? attributes.homeID : attributes.awayID
    if let image = UIImage(named: "team-\(attributes.league)-\(id)") {
        Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
    } else {
        Text(home ? attributes.home : attributes.away).font(.system(size: size * 0.28, weight: .bold))
            .frame(width: size, height: size).background(.white.opacity(0.08), in: Circle())
    }
}
