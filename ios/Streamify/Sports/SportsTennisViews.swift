import SwiftUI

struct SportsLeagueIcon: View {
    let league: SportsLeague
    var body: some View {
        if league == .tennis {
            Image(systemName: "tennisball.fill").resizable().scaledToFit().foregroundStyle(league.accent)
        } else {
            Image("league-\(league.rawValue)").resizable().scaledToFit()
        }
    }
}

struct SportsTennisScoreRow: View {
    let game: SportsGame
    let player: SportsTeam
    var preview = false

    var body: some View {
        let metadata = game.tennis
        let sets = player.id == game.away.id ? metadata?.awaySets ?? [] : metadata?.homeSets ?? []
        let point = player.id == game.away.id ? metadata?.awayPoint : metadata?.homePoint
        HStack(spacing: 7) {
            if let logo = player.logoURL { RemoteArtwork(url: logo, contentMode: .fit).frame(width: 23, height: 18) }
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name).font(.system(size: 14, weight: game.winner?.id == player.id ? .bold : .semibold))
                    .lineLimit(2).foregroundStyle(game.winner != nil && game.winner?.id != player.id ? AppTheme.muted : AppTheme.foreground)
                if !player.record.isEmpty { Text(player.record).font(.caption2).foregroundStyle(AppTheme.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !preview {
                if metadata?.servingID == player.id {
                    Image(systemName: "tennisball.fill").font(.system(size: 8)).foregroundStyle(SportsLeague.tennis.accent)
                        .accessibilityLabel("\(player.name) serving")
                }
                ForEach(Array(sets.enumerated()), id: \.offset) { _, value in
                    Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.65).frame(width: value.count > 2 ? 36 : 23)
                }
                if let point, !point.isEmpty, game.isLive {
                    Text(point).font(.subheadline.monospacedDigit().bold()).frame(width: 30, height: 28)
                        .background(AppTheme.foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                if sets.isEmpty && game.state != "pre" { Text("—").foregroundStyle(AppTheme.muted).frame(width: 23) }
                SportsWinnerChevron(visible: game.winner?.id == player.id)
            }
        }.frame(minHeight: 44)
    }
}

struct SportsTennisGroup: Identifiable {
    let id: String
    let tour: SportsTennisTour
    let tournament: String
    let discipline: String
    let games: [SportsGame]

    static func groups(_ games: [SportsGame]) -> [SportsTennisGroup] {
        let grouped = Dictionary(grouping: games.filter { $0.tennis != nil }) { $0.tennis!.groupID }
        return grouped.compactMap { key, values -> SportsTennisGroup? in
            guard let metadata = values.first?.tennis else { return nil }
            return SportsTennisGroup(id: key, tour: metadata.tour, tournament: metadata.tournament,
                discipline: metadata.discipline, games: values.sorted {
                    if $0.date != $1.date { return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                    return $0.id < $1.id
                })
        }.sorted {
            let a = SportsTennisTour.allCases.firstIndex(of: $0.tour) ?? 0
            let b = SportsTennisTour.allCases.firstIndex(of: $1.tour) ?? 0
            if a != b { return a < b }
            if $0.tournament != $1.tournament { return $0.tournament.localizedStandardCompare($1.tournament) == .orderedAscending }
            return $0.discipline < $1.discipline
        }
    }
}
