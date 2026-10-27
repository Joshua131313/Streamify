import SwiftUI

struct SportsPlayByPlayView: View {
    let game: SportsGame
    let periods: [SportsPlayPeriod]
    @State private var selectedPeriod: Int?
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if periods.isEmpty {
                StateMessage(symbol: "list.bullet", title: "Play-by-play unavailable", message: "The game feed has not supplied a play log.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Pill(title: "All", selected: selectedPeriod == nil) { selectedPeriod = nil }
                        ForEach(periods) { period in
                            Pill(title: game.league.periodTitle(period.number), selected: selectedPeriod == period.number) {
                                selectedPeriod = period.number; expanded.insert(period.number)
                            }.accessibilityIdentifier("sports-play-period-filter-\(period.number)")
                        }
                    }
                }
                ForEach(periods.filter { selectedPeriod == nil || $0.number == selectedPeriod }) { period in
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(period.number) }, set: { value in
                        AppHaptics.tap()
                        if value { expanded.insert(period.number) } else { expanded.remove(period.number) }
                    })) {
                        VStack(spacing: 0) {
                            ForEach(period.plays) { play in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(play.clock.isEmpty ? "—" : play.clock).font(.caption.monospacedDigit())
                                        .foregroundStyle(AppTheme.muted).frame(width: 42, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(play.text).font(.subheadline.weight(play.scoring ? .semibold : .regular))
                                            .fixedSize(horizontal: false, vertical: true)
                                        if !play.awayScore.isEmpty && !play.homeScore.isEmpty {
                                            Text("\(game.away.abbreviation) \(play.awayScore)  ·  \(game.home.abbreviation) \(play.homeScore)")
                                                .font(.caption2.monospacedDigit()).foregroundStyle(AppTheme.muted)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(.vertical, 12)
                                    .accessibilityElement(children: .combine).accessibilityIdentifier("sports-play-\(play.id)")
                                if play.id != period.plays.last?.id { Divider().overlay(AppTheme.border.opacity(0.4)) }
                            }
                        }.padding(.top, 4)
                    } label: {
                        HStack {
                            Text(game.league.periodTitle(period.number)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(period.plays.count) plays").font(.caption).foregroundStyle(AppTheme.muted)
                        }.frame(minHeight: 36)
                    }.tint(AppTheme.foreground).padding(.horizontal, 12).padding(.vertical, 5)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.onAppear { if expanded.isEmpty, let first = periods.first { expanded.insert(first.number) } }
    }
}

struct SportsGamePlayersView: View {
    let game: SportsGame
    let groups: [SportsPlayerStatGroup]
    @State private var teamID: String?
    @State private var categoryID: String?
    private var selectedTeam: String { teamID ?? game.away.id }
    private var teamGroups: [SportsPlayerStatGroup] { groups.filter { $0.teamID == selectedTeam } }
    private var activeGroup: SportsPlayerStatGroup? { teamGroups.first { $0.id == categoryID } ?? teamGroups.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach([game.away, game.home]) { team in
                    Button { teamID = team.id; categoryID = nil } label: {
                        HStack(spacing: 7) {
                            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 22, height: 22)
                            Text(team.abbreviation.isEmpty ? team.name : team.abbreviation).font(.subheadline.weight(.semibold))
                        }.frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selectedTeam == team.id ? AppTheme.canvas : AppTheme.foreground)
                            .background(selectedTeam == team.id ? AppTheme.foreground : AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("\(team.name) players")
                        .accessibilityIdentifier("sports-players-team-\(team.id)")
                        .accessibilityAddTraits(selectedTeam == team.id ? .isSelected : [])
                }
            }
            if teamGroups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(teamGroups) { group in
                            Pill(title: group.title.isEmpty ? "Stats" : group.title, selected: activeGroup?.id == group.id) { categoryID = group.id }
                        }
                    }
                }
            }
            if let group = activeGroup { SportsPlayerGameTable(group: group) }
            else { StateMessage(symbol: "person.3", title: "Player stats unavailable", message: "Individual stats will appear when the game feed provides them.") }
        }
    }
}

private struct SportsPlayerGameTable: View {
    let group: SportsPlayerStatGroup
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var playerWidth: CGFloat = 154
    @ScaledMetric(relativeTo: .caption) private var columnWidth: CGFloat = 48
    private let headerHeight: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("PLAYER").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: headerHeight).padding(.leading, 10)
                ForEach(Array(group.players.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 7) {
                        AsyncImage(url: sportsHTTPSURL(player.photo)) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() }
                            else { Image(systemName: "person.fill").font(.system(size: 16)).foregroundStyle(AppTheme.muted) }
                        }.frame(width: 28, height: 28).background(AppTheme.controlFill, in: Circle())
                            .clipShape(Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name).font(.caption.weight(.semibold)).lineLimit(2)
                            Text(player.didNotPlay ? "DNP" : [player.position, player.number.isEmpty ? "" : "#\(player.number)"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(AppTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 8).frame(height: rowHeight)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("sports-player-row-\(player.id)")
                }
            }.frame(width: min(210, playerWidth))
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(group.labels.indices, id: \.self) { column in
                            VStack(spacing: 0) {
                                Text(group.labels[column]).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).frame(height: headerHeight)
                                    .accessibilityLabel(group.descriptions.indices.contains(column) ? group.descriptions[column] : group.labels[column])
                                ForEach(Array(group.players.enumerated()), id: \.element.id) { index, player in
                                    Text(player.values.indices.contains(column) ? player.values[column] : "—")
                                        .font(.caption.monospacedDigit().weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                                        .frame(maxWidth: .infinity).frame(height: rowHeight)
                                        .accessibilityLabel("\(player.name), \(group.labels[column])")
                                        .accessibilityIdentifier("sports-player-stat-\(player.id)-\(column)")
                                }
                            }.frame(width: max(columnWidth, geometry.size.width / CGFloat(max(1, group.labels.count))))
                        }
                    }
                }
            }
        }.frame(height: headerHeight + rowHeight * CGFloat(group.players.count))
            .background {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    ForEach(group.players.indices, id: \.self) { index in
                        Rectangle().fill(index.isMultiple(of: 2) ? Color.clear : AppTheme.foreground.opacity(0.025))
                            .frame(height: rowHeight)
                    }
                }
            }
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 0.5) }
    }
}
