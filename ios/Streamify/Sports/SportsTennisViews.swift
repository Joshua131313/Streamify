import SwiftUI

struct SportsLeagueIcon: View {
    let league: SportsLeague
    var body: some View {
        if league == .tennis {
            Image(systemName: "tennisball.fill").resizable().scaledToFit().padding(3).foregroundStyle(league.accent)
        } else {
            Image("league-\(league.rawValue)").resizable().scaledToFit()
        }
    }
}

struct SportsTennisScoreRow: View {
    let game: SportsGame
    let player: SportsTeam
    var preview = false
    @State private var portraitURL: URL?


    var body: some View {
        let metadata = game.tennis
        let sets = player.id == game.away.id ? metadata?.awaySets ?? [] : metadata?.homeSets ?? []
        let point = player.id == game.away.id ? metadata?.awayPoint : metadata?.homePoint
        HStack(spacing: 7) {
            if let logo = player.logoURL { RemoteArtwork(url: logo, contentMode: .fit).frame(width: 23, height: 18) }
            if let photo = portraitURL ?? player.portrait.flatMap(sportsHTTPSURL) {
                AsyncImage(url: photo) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: 30, height: 30, alignment: .top).clipShape(Circle()).accessibilityLabel("\(player.name) photo")
                    .contextMenu { if let credits = SportsTennisPortraits.credits(photo) { Link("Photo credits", destination: credits) } }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(player.tennisDisplayName).font(.system(size: 14, weight: game.winner?.id == player.id ? .bold : .semibold))
                    .lineLimit(2).foregroundStyle(game.winner != nil && game.winner?.id != player.id ? AppTheme.muted : AppTheme.foreground)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !preview {
                if game.isLive, metadata?.servingID == player.id {
                    Image(systemName: "tennis.racket").font(.system(size: 14)).foregroundStyle(AppTheme.foreground)
                        .accessibilityLabel("\(player.name) serving")
                        .accessibilityIdentifier("tennis-serving-\(player.id)")
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
        }.frame(minHeight: 44).task(id: game.id) {
            portraitURL = await SportsTennisPortraits.shared.photos(game)[player.id]
        }
    }
}

actor SportsTennisPortraits {
    static let shared = SportsTennisPortraits()
    private var flights: [String: Task<[String: URL], Never>] = [:]
    func photos(_ game: SportsGame) async -> [String: URL] {
        #if DEBUG
        if PreviewFixtures.enabled { return [:] }
        #endif
        if let flight = flights[game.id] { return await flight.value }
        let task = Task {
            async let away = Self.portrait(game.away)
            async let home = Self.portrait(game.home)
            let values = await [(game.away.id, away), (game.home.id, home)]
            return Dictionary(uniqueKeysWithValues: values.compactMap { id, image in image.map { (id, $0) } })
        }
        if flights.count >= 96 { flights.removeValue(forKey: flights.keys.sorted().first!) }
        flights[game.id] = task
        return await task.value
    }

    private static func portrait(_ player: SportsTeam) async -> URL? {
        if let url = player.portrait.flatMap(sportsHTTPSURL) { return url }
        guard !player.name.contains("/"), player.name.count <= 100,
              let name = player.name.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(name)") else { return nil }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = 5
            request.setValue("Streamify/1.1 (https://github.com/Joshua131313/Streamify)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 128 * 1024,
                  let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  raw.sportsText("description").localizedCaseInsensitiveContains("tennis"),
                  SportsSourceIdentity.normalized(raw.sportsText("title")) == SportsSourceIdentity.normalized(player.name),
                  let image = sportsHTTPSURL(raw.sportsObject("thumbnail").sportsText("source")),
                  ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(image.host ?? "") else { return nil }
            return image
        } catch { return nil }
    }

    nonisolated static func credits(_ image: URL) -> URL? {
        let parts = image.path.components(separatedBy: "/")
        guard ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(image.host ?? ""),
              let thumb = parts.firstIndex(of: "thumb"), parts.count > thumb + 3 else { return nil }
        var value = URLComponents(); value.scheme = "https"; value.host = "commons.wikimedia.org"
        value.path = "/wiki/File:\(parts[thumb + 3])"
        return value.url
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
