import SwiftUI
import WidgetKit
import ActivityKit

struct TrackedGameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SportsTrackedGameAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STREAMIFY · \(context.attributes.league == "college-football" ? "CFB" : context.attributes.league.uppercased())")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(context.isStale ? "Last score received" : context.state.status).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text(context.attributes.away).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(context.state.awayScore.isEmpty ? "–" : context.state.awayScore)  –  \(context.state.homeScore.isEmpty ? "–" : context.state.homeScore)")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Spacer()
                    Text(context.attributes.home).font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 10) {
                    if let situation = context.state.situation { Text(situation).font(.caption2).lineLimit(1) }
                    else { Text(context.state.updatedAt, style: .time).font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    if !context.state.final {
                        Link(destination: context.attributes.watchURL) {
                            HStack(spacing: 6) { Text("Watch"); Image(systemName: "play.fill").font(.system(size: 10)) }
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }.padding(16).widgetURL(context.attributes.watchURL)
        } dynamicIsland: { context in
            DynamicIsland(expanded: {
                DynamicIslandExpandedRegion(.leading) { Text("\(context.attributes.away)  \(context.state.awayScore)").font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.homeScore)  \(context.attributes.home)").font(.headline) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.isStale ? "Last score received" : context.state.situation ?? context.state.status).font(.caption)
                        Spacer()
                        Link("Watch", destination: context.attributes.watchURL).font(.caption.weight(.semibold))
                    }
                }
            }, compactLeading: { Text("\(context.attributes.away) \(context.state.awayScore)").font(.caption2) },
              compactTrailing: { Text("\(context.state.homeScore) \(context.attributes.home)").font(.caption2) },
              minimal: { Image(systemName: "sportscourt") })
              .widgetURL(context.attributes.watchURL)
        }
    }
}
