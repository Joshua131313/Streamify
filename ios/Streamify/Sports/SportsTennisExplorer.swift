import Foundation
import CoreFoundation

/// Published scoreboard state supplements schedule-only Challenger rows. A
/// scheduled start time is never evidence that a match has actually started.
enum TennisLiveFeed {
    static func runtime(_ html: String) throws -> [String: Any] {
        guard html.utf8.count <= 4 * 1024 * 1024,
              let body = captures("<script\\b[^>]*>\\s*window\\.TENNISLIVE_RUNTIME\\s*=\\s*([\\s\\S]*?)</script>", html).first?.first,
              let end = body.lastIndex(of: "}"),
              let object = try JSONSerialization.jsonObject(with: Data(body[...end].utf8)) as? [String: Any]
        else { throw SportsServiceError.invalidResponse }
        return object
    }

    static func parse(_ html: String) throws -> [SportsGame] {
        let raw = try runtime(html)
        guard raw["homepageTournaments"] is [[String: Any]] else { throw SportsServiceError.invalidResponse }
        let observedAt = (raw["serverTimestamp"] as? NSNumber).flatMap { value -> Double? in
            let timestamp = value.doubleValue
            return CFGetTypeID(value) != CFBooleanGetTypeID() && timestamp.isFinite && timestamp > 0 ? timestamp : nil
        }
        return raw.sportsObjects("homepageTournaments").flatMap { group -> [SportsGame] in
            let path = group.sportsText("url"), tour = group.sportsText("tour")
            guard ["atp", "wta"].contains(tour), group["junior"] as? Bool != true,
                  path.range(of: "^/(atp-men|wta-women)/[a-z0-9-]+-[0-9]{4}/$", options: .regularExpression) != nil,
                  group.sportsText("name").range(of: "\\b[MW][0-9]{2,3}\\b|junior", options: [.regularExpression, .caseInsensitive]) == nil
            else { return [] }
            return group.sportsObjects("matches").compactMap { match in
                let players = match.sportsObjects("players")
                let state = ["live": "in", "finished": "post", "scheduled": "pre", "upcoming": "pre"][match.sportsText("state")]
                guard players.count == 2, let state,
                      let start = match["startTimestamp"] as? NSNumber, CFGetTypeID(start) != CFBooleanGetTypeID(),
                      start.doubleValue.isFinite, start.doubleValue > 0,
                      let route = historyURL(match.sportsText("url")),
                      let a = player(players[0], tour: tour), let b = player(players[1], tour: tour), a.id != b.id else { return nil }
                let tournament = group.sportsText("tournamentId")
                guard tournament.range(of: "^[0-9]{1,18}$", options: .regularExpression) != nil else { return nil }
                let playerIDs = players.map { $0.sportsText("id") }
                let eventID = "tennislive-\(tour)-\(tournament)-\(playerIDs[0])-\(playerIDs[1])"
                let name = group.sportsText("name")
                let displayName = name.hasPrefix("WTA Finals") ? name : name.replacingOccurrences(of: "^(ATP|WTA) ", with: "", options: .regularExpression)
                var metadata = SportsTennisMatch(tour: tour == "wta" ? .wta : path.contains("challenger") || group["rank"] as? Int == 1 ? .challenger : .atp,
                    tournament: displayName, tournamentID: "tl-\(tour)-\(tournament)",
                    discipline: match["mixed"] as? Bool == true ? "Mixed Doubles" : match["doubles"] as? Bool == true ? "Doubles" : "Singles",
                    round: rounds[group.sportsText("stageCode")] ?? "",
                    awaySets: sets(players[0]), homeSets: sets(players[1]), source: "tennislive", historyURL: route,
                    tennisLiveEventID: eventID, tennisLiveDraw: draw(match, group: group, playerIDs: playerIDs), tennisLiveObservedAt: observedAt)
                let points = match["points"] as? [Any] ?? []
                if state == "in" {
                    metadata.awayPoint = points.indices.contains(0) ? point(points[0]) : nil
                    metadata.homePoint = points.indices.contains(1) ? point(points[1]) : nil
                    if let index = match["server"] as? Int, [0, 1].contains(index) { metadata.servingID = index == 0 ? a.id : b.id }
                }
                if state == "post", let winner = match["winnerId"] as? NSNumber {
                    metadata.winnerID = players[0].sportsText("id") == winner.stringValue ? a.id : players[1].sportsText("id") == winner.stringValue ? b.id : nil
                }
                return SportsGame(eventID: eventID,
                    league: .tennis, date: Date(timeIntervalSince1970: start.doubleValue), state: state,
                    status: state == "post" ? "Final" : state == "in" ? match.sportsText("setLabel") : "Scheduled",
                    home: b, away: a, venue: "", broadcasts: "", link: route, tennis: metadata)
            }
        }
    }

    static func point(_ raw: Any?) -> String? {
        let text: String
        if let value = raw as? String { text = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        else if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { text = value.stringValue }
        else { return nil }
        if ["A", "AD", "ADV", "ADVANTAGE"].contains(text) { return "AD" }
        guard text.range(of: "^(0|[1-9][0-9]{0,2})$", options: .regularExpression) != nil else { return nil }
        return text
    }

    private static let rounds = ["round_robin": "Group Stage", "quarterfinal": "Quarterfinal", "semifinal": "Semifinal", "final": "Final",
        "round_1": "Round 1", "round_2": "Round 2", "round_3": "Round 3", "round_4": "Round 4"]

    private static func draw(_ match: [String: Any], group: [String: Any], playerIDs: [String]) -> String? {
        let round = group.sportsText("roundId"), position = match.sportsText("drawPosition")
        guard [round, position].allSatisfy({ $0.range(of: "^[0-9]{1,8}$", options: .regularExpression) != nil }),
              let a = UInt64(playerIDs[0]), let b = UInt64(playerIDs[1]),
              match.sportsText("favoriteKey") == "m1:\(group.sportsText("tour")):\(group.sportsText("tournamentId")):\(round):\(position):\(min(a, b)):\(max(a, b))" else { return nil }
        return "\(round)-\(position)"
    }

    static func merge(_ scheduled: [SportsGame], live: [SportsGame]) -> [SportsGame] {
        var result = SportsScheduleDayPolicy.canonicalGames(scheduled)
        let snapshots = canonicalSnapshots(live)
        let matches = snapshots.map { snapshot in result.indices.filter { sameMatch(result[$0], snapshot) } }
        var claims: [Int: Int] = [:]
        for candidates in matches { for index in candidates { claims[index, default: 0] += 1 } }
        for (offset, snapshot) in snapshots.enumerated() {
            guard matches[offset].count == 1, let index = matches[offset].first, claims[index] == 1 else {
                result.append(snapshot); continue
            }
            let original = result[index]
            result[index] = overlay(snapshot, onto: original)
        }
        return SportsScheduleDayPolicy.canonicalGames(result)
    }

    private static func canonicalSnapshots(_ games: [SportsGame]) -> [SportsGame] {
        var snapshots: [String: SportsGame] = [:]
        for game in games {
            let key: String
            if let metadata = game.tennis, let draw = metadata.tennisLiveDraw {
                key = ([metadata.tournamentID, draw] + [game.away.id, game.home.id].sorted()).joined(separator: ":")
            } else { key = game.eventID }
            if let old = snapshots[key], shouldKeep(old, over: game) { continue }
            snapshots[key] = game
        }
        return Dictionary(grouping: snapshots.values, by: \.eventID).values.flatMap { occurrences in
            occurrences.sorted { a, b in
                if a.date != b.date { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }
                return (a.tennis?.tennisLiveDraw ?? "") < (b.tennis?.tennisLiveDraw ?? "")
            }.enumerated().map { index, game in
                guard index > 0, let draw = game.tennis?.tennisLiveDraw else { return game }
                return SportsGame(eventID: "\(game.eventID)-\(draw)", league: game.league, date: game.date,
                    state: game.state, status: game.status, home: game.home, away: game.away, venue: game.venue,
                    broadcasts: game.broadcasts, link: game.link, tennis: game.tennis)
            }
        }
    }

    static func findGame(eventID: String, in games: [SportsGame]) -> SportsGame? {
        if let exact = games.first(where: { $0.eventID == eventID }) { return exact }
        let candidates = games.filter { game in
            guard let tennis = game.tennis, let base = tennis.tennisLiveEventID else { return false }
            let reverse = base.split(separator: "-")
            guard reverse.count == 5 else { return false }
            let reversed = "\(reverse[0])-\(reverse[1])-\(reverse[2])-\(reverse[4])-\(reverse[3])"
            if eventID == base || eventID == reversed { return true }
            return tennis.tennisLiveDraw.map { eventID == "\(base)-\($0)" || eventID == "\(reversed)-\($0)" } == true
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func phase(_ game: SportsGame) -> Int { game.isFinal ? 2 : game.isLive ? 1 : 0 }
    private static func pointCount(_ game: SportsGame) -> Int { [game.tennis?.awayPoint, game.tennis?.homePoint].compactMap { $0 }.count }

    private static func shouldKeep(_ old: SportsGame, over new: SportsGame) -> Bool {
        if phase(old) != phase(new) { return phase(old) > phase(new) }
        if let oldTime = old.tennis?.tennisLiveObservedAt, let newTime = new.tennis?.tennisLiveObservedAt, oldTime != newTime {
            return oldTime > newTime
        }
        return pointCount(old) > pointCount(new)
    }

    private static func overlay(_ snapshot: SportsGame, onto original: SportsGame) -> SportsGame {
        guard var metadata = original.tennis, let fresh = snapshot.tennis else { return original }
        metadata.historyURL = fresh.historyURL ?? metadata.historyURL
        metadata.tennisLiveEventID = fresh.tennisLiveEventID
        metadata.tennisLiveDraw = fresh.tennisLiveDraw
        if metadata.round.isEmpty { metadata.round = fresh.round }
        let takeScore = phase(snapshot) >= phase(original)
        let preferred = takeScore ? snapshot : original
        var a = original.away, b = original.home
        if takeScore {
            let aligned = sameSide(original.away.name, snapshot.away.name, doubles: metadata.isDoubles)
            let away = aligned ? snapshot.away : snapshot.home, home = aligned ? snapshot.home : snapshot.away
            let awaySets = aligned ? fresh.awaySets : fresh.homeSets, homeSets = aligned ? fresh.homeSets : fresh.awaySets
            let sameScore = original.isLive && awaySets == metadata.awaySets && homeSets == metadata.homeSets
            let awayPoint = aligned ? fresh.awayPoint : fresh.homePoint, homePoint = aligned ? fresh.homePoint : fresh.awayPoint
            if !awaySets.isEmpty { metadata.awaySets = awaySets }
            if !homeSets.isEmpty { metadata.homeSets = homeSets }
            metadata.awayPoint = snapshot.isLive ? awayPoint ?? (sameScore ? metadata.awayPoint : nil) : nil
            metadata.homePoint = snapshot.isLive ? homePoint ?? (sameScore ? metadata.homePoint : nil) : nil
            if let server = fresh.servingID { metadata.servingID = server == away.id ? a.id : server == home.id ? b.id : nil }
            else if !snapshot.isLive || !sameScore { metadata.servingID = nil }
            if let winner = fresh.winnerID { metadata.winnerID = winner == away.id ? a.id : winner == home.id ? b.id : nil }
            if !away.score.isEmpty { a.score = away.score }
            if !home.score.isEmpty { b.score = home.score }
        }
        return SportsGame(eventID: original.eventID, league: .tennis, date: original.date ?? snapshot.date,
            state: preferred.state, status: preferred.status, home: b, away: a, venue: original.venue,
            broadcasts: original.broadcasts, link: original.link, tennis: metadata)
    }

    static func sameMatch(_ a: SportsGame, _ b: SportsGame) -> Bool {
        guard let at = a.tennis, let bt = b.tennis, at.tour == bt.tour, at.isDoubles == bt.isDoubles,
              at.discipline.lowercased().contains("mixed") == bt.discipline.lowercased().contains("mixed"),
              let ad = a.date, let bd = b.date else { return false }
        let ar = roundKey(at.round), br = roundKey(bt.round)
        if !ar.isEmpty, !br.isEmpty, ar != br { return false }
        let difference = abs(ad.timeIntervalSince(bd))
        guard difference <= (at.timeConfirmed ? 30 * 60 : 2 * 3600) else { return false }
        func matches(_ first: SportsTeam, _ second: SportsTeam) -> Bool { sameSide(first.name, second.name, doubles: at.isDoubles) }
        guard (matches(a.away, b.away) && matches(a.home, b.home)) || (matches(a.away, b.home) && matches(a.home, b.away)) else { return false }
        return tournamentMatches(a, b) || (difference <= 30 * 60 && (finalsAlias(a, b) || (!ar.isEmpty && ar == br && cityAlias(a, b))))
    }

    private static func sameSide(_ a: String, _ b: String, doubles: Bool) -> Bool {
        if !doubles { return samePlayer(a, b) }
        let x = a.split(whereSeparator: { $0 == "/" || $0 == "&" }).map(String.init)
        let y = b.split(whereSeparator: { $0 == "/" || $0 == "&" }).map(String.init)
        guard x.count == 2, y.count == 2 else { return false }
        func matches(_ first: String, _ second: String) -> Bool {
            if samePlayer(first, second) { return true }
            let a = words(first), b = words(second)
            return a.count == 2 && b.count == 2 && (a + b).allSatisfy { $0.count > 1 } && a == Array(b.reversed())
        }
        return (matches(x[0], y[0]) && matches(x[1], y[1])) || (matches(x[0], y[1]) && matches(x[1], y[0]))
    }

    static func samePlayer(_ a: String, _ b: String) -> Bool {
        let x = words(a), y = words(b)
        if x == y { return !x.isEmpty }
        // Some feeds omit middle given names (Leylah Annie Fernandez vs
        // Leylah Fernandez). Keep both the full given name and surname exact;
        // initials alone or two different supplied middle names are not enough.
        if !a.contains("/"), !b.contains("/"), !a.contains("&"), !b.contains("&"),
           min(x.count, y.count) == 2, max(x.count, y.count) > 2,
           x.first == y.first, x.last == y.last,
           let given = x.first, given.count > 1, let surname = x.last, surname.count > 1 {
            return true
        }
        func abbreviated(_ short: [String], _ full: [String]) -> Bool {
            guard short.count >= 2, full.count >= 2, short.dropFirst().allSatisfy({ $0.count == 1 }),
                  short[0] == full.last, short[1].first == full.first?.first else { return false }
            return true
        }
        return abbreviated(x, y) || abbreviated(y, x)
    }

    static func historyURL(_ value: String) -> String? {
        let path = value.hasPrefix("https://www.tennislive.net/") ? String(value.dropFirst("https://www.tennislive.net".count)) : value
        guard path.range(of: "^/(atp|wta)/match/[A-Za-z0-9-]+-VS-[A-Za-z0-9-]+/[a-z0-9-]+-[0-9]{4}/$", options: .regularExpression) != nil else { return nil }
        return "https://www.tennislive.net\(path)"
    }

    static func pointWinner(previous: String, current: String) -> Int? {
        let a = previous.components(separatedBy: "–"), b = current.components(separatedBy: "–")
        guard a.count == 2, b.count == 2 else { return nil }
        if a == ["A", "40"], b == ["40", "40"] { return 1 }
        if a == ["40", "A"], b == ["40", "40"] { return 0 }
        for index in 0...1 where a[1 - index] == b[1 - index] {
            if ["0:15", "15:30", "30:40", "40:A"].contains("\(a[index]):\(b[index])") { return index }
            if let old = Int(a[index]), let new = Int(b[index]), new == old + 1 { return index }
        }
        return nil
    }

    static func history(_ html: String, game: SportsGame) throws -> [TennisHistorySet] {
        let raw = try runtime(html), names = raw["matchDetailPlayerNames"] as? [String] ?? []
        guard names.count == 2,
              (samePlayer(names[0], game.away.name) && samePlayer(names[1], game.home.name)) ||
              (samePlayer(names[1], game.away.name) && samePlayer(names[0], game.home.name)),
              let timestamp = raw["matchDetailReferenceTimestamp"] as? NSNumber, let date = game.date,
              abs(date.timeIntervalSince1970 - timestamp.doubleValue) < 36 * 3600 else { throw SportsServiceError.invalidResponse }
        let reversed = !samePlayer(names[0], game.away.name)
        func orient(_ value: String) -> String {
            let pair = value.components(separatedBy: "–")
            return reversed && pair.count == 2 ? pair.reversed().joined(separator: "–") : value
        }
        return captures("<section\\b[^>]*data-set-panel=[\"']([1-5])[\"'][^>]*>([\\s\\S]*?)</section>", html).compactMap { panel in
            guard let number = Int(panel[0]) else { return nil }
            let chunks = panel[1].components(separatedBy: "class=\"tl-progress-game").dropFirst()
            let games = chunks.enumerated().map { index, chunk in
                let score = captures("<strong\\b[^>]*>([\\s\\S]*?)</strong>", chunk).first.map { plain($0[0]) } ?? ""
                let server = captures("data-progress-server-ball[^>]*data-player-index=[\"']([01])[\"']", chunk).first.flatMap { Int($0[0]) }.map { names[$0] }
                let winner = captures("data-progress-outcome[^>]*>([\\s\\S]*?)</span>", chunk).first.map { plain($0[0]).replacingOccurrences(of: " wins the game", with: "") }
                // Only scores published inside this game's point summary.
                let summary = chunk.components(separatedBy: "text-xs text-black/45").dropFirst().first ?? ""
                let text = plain(summary.components(separatedBy: "</div>").first ?? "")
                let points = captures("(?<![0-9A-Za-z])([0-9]{1,2}|A)-(0|15|30|40|A|[0-9]{1,2})(?![0-9A-Za-z])", text).map { "\($0[0])–\($0[1])" }
                return TennisHistoryGame(number: index + 1, score: orient(score.replacingOccurrences(of: "-", with: "–")), server: server, winner: winner,
                    isBreak: chunk.contains(">Serve lost</span>"), points: points.map(orient))
            }
            return games.isEmpty ? nil : TennisHistorySet(number: number, games: games)
        }
    }

    private static func tournament(_ value: String) -> String {
        var seen = Set<String>()
        return words(value).filter { !["atp", "wta", "challenger", "open", "tennis", "125"].contains($0) &&
            !((1900...2100).contains(Int($0) ?? 0)) && seen.insert($0).inserted }.joined()
    }

    private static func roundKey(_ value: String) -> String {
        let key = words(value).joined()
        switch key {
        case "groupstage", "roundrobin": return "group"
        case "quarterfinals", "roundof8": return "quarterfinal"
        case "semifinals", "roundof4": return "semifinal"
        case "1stround", "firstround": return "round1"
        case "2ndround", "secondround": return "round2"
        case "3rdround", "thirdround": return "round3"
        case "4thround", "fourthround": return "round4"
        default: return key
        }
    }

    private static func tennisLiveTournament(_ game: SportsGame) -> String? {
        guard let route = game.tennis?.historyURL.flatMap(historyURL) else { return nil }
        return URL(string: route)?.lastPathComponent
    }

    private static func sameEdition(_ official: SportsGame, liveSlug: String) -> Bool {
        let year = liveSlug.suffix(4)
        guard year.count == 4, (1900...2100).contains(Int(year) ?? 0), let tournament = official.tennis?.tournamentID else { return false }
        return tournament.hasSuffix("-\(year)")
    }

    private static func finalsAlias(_ official: SportsGame, _ live: SportsGame) -> Bool {
        guard official.tennis?.tour == .wta, live.tennis?.tour == .wta,
              let title = official.tennis?.tournament, let slug = tennisLiveTournament(live),
              slug.hasPrefix("wta-finals-"), sameEdition(official, liveSlug: slug) else { return false }
        let tokens = words(title)
        return zip(tokens, tokens.dropFirst()).contains { $0.0 == "wta" && $0.1 == "finals" }
    }

    private static func cityAlias(_ official: SportsGame, _ live: SportsGame) -> Bool {
        guard official.tennis?.source == "espn", official.venue.contains(","),
              let city = official.venue.split(separator: ",").first,
              let slug = tennisLiveTournament(live), sameEdition(official, liveSlug: slug) else { return false }
        let citySlug = words(String(city)).joined(separator: "-")
        return citySlug.count >= 4 && slug.dropLast(5).hasSuffix("-\(citySlug)")
    }

    private static func tournamentMatches(_ a: SportsGame, _ b: SportsGame) -> Bool {
        func aliases(_ game: SportsGame) -> [String] {
            var names = [game.tennis?.tournament ?? ""]
            // The published route retains the official event name even when
            // the live header abbreviates it to its host city (e.g. Vienna).
            if let slug = tennisLiveTournament(game) {
                names.append(slug.replacingOccurrences(of: "-", with: " "))
            }
            return names.map(tournament).filter { !$0.isEmpty }
        }
        return aliases(a).contains { x in aliases(b).contains { y in
            x == y || (min(x.count, y.count) >= 6 && (x.hasPrefix(y) || y.hasPrefix(x)))
        } }
    }
    private static func words(_ value: String) -> [String] {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    private static func player(_ raw: [String: Any], tour: String) -> SportsTeam? {
        let id = raw.sportsText("id"), name = raw.sportsText("name")
        guard id.range(of: "^[0-9]{1,18}$", options: .regularExpression) != nil, !name.isEmpty else { return nil }
        return SportsTeam(id: "tl-\(tour)-\(id)", name: name, abbreviation: name, logo: "", score: raw.sportsText("setsWon"),
            record: Int(raw.sportsText("seed")).map { "Seed \($0)" } ?? "", streamNames: [name])
    }
    private static func sets(_ raw: [String: Any]) -> [String] {
        (raw["sets"] as? [Any] ?? []).prefix(5).map { value in
            let number = value as? NSNumber ?? (value as? [String: Any])?["score"] as? NSNumber
            return number.map { (0...99).contains($0.intValue) ? $0.stringValue : "—" } ?? "—"
        }
    }
    private static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (1..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
        }
    }
    private static func plain(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Challenger listings are published as paired HTML rows. Parsing stays inside
/// dated result tables; unrelated players, prices and advertising are ignored.
enum SportsTennisExplorer {
    static func parse(_ html: String) throws -> [SportsGame] {
        guard html.utf8.count <= 2 * 1024 * 1024,
              let zoneText = matches("<span\\b[^>]*class=[\"'][^\"']*\\btimezone\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</span>", html).first?[1],
              let zone = matches("GMT([+-][0-9]{1,2})(?::([0-9]{2}))?", text(zoneText)).first,
              let hours = Int(zone[1]), abs(hours) <= 14 else { throw SportsServiceError.invalidResponse }
        let minutes = Int(zone[2]) ?? 0
        guard minutes < 60, let timezone = TimeZone(secondsFromGMT: (hours * 60 + (hours < 0 ? -minutes : minutes)) * 60) else { throw SportsServiceError.invalidResponse }
        let regex = try NSRegularExpression(pattern: "<table\\b[^>]*class=[\"'][^\"']*\\bresult\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</table>", options: [.caseInsensitive])
        let whole = html as NSString
        var previousEnd = 0, result: [SportsGame] = [], datedTables = 0
        for table in regex.matches(in: html, range: NSRange(location: 0, length: whole.length)) {
            let prefix = whole.substring(with: NSRange(location: previousEnd, length: table.range.location - previousEnd))
            previousEnd = table.range.location + table.range.length
            guard let date = matches("<li\\b[^>]*class=[\"'][^\"']*\\bset\\b[^\"']*[\"'][^>]*>[\\s\\S]*?<span\\b[^>]*class=[\"'][^\"']*\\btab\\b[^\"']*[\"'][^>]*>\\s*([0-9]{1,2})\\.\\s*([0-9]{1,2})\\.\\s*([0-9]{4})", prefix).last else { continue }
            datedTables += 1
            let rows = matches("<tr\\b([^>]*)>([\\s\\S]*?)</tr>", whole.substring(with: table.range(at: 1)))
            var active: (id: String, title: String, doubles: Bool)?
            var pending: (id: String, html: String, tournament: (id: String, title: String, doubles: Bool))?
            for row in rows {
                if classes(row[1]).contains("head") {
                    pending = nil; active = nil
                    guard let link = links(row[2]).first(where: { $0.href.range(of: "^/[a-z0-9-]+-challenger/[0-9]{4}/atp-men/(?:\\?type=double)?$", options: .regularExpression) != nil }) else { continue }
                    active = (link.href, text(link.html), row[2].contains("type-men4") || link.href.contains("type=double"))
                    continue
                }
                guard let tournament = active, let id = attribute("id", row[1]), id.range(of: "^r[0-9]+b?$", options: .regularExpression) != nil else { pending = nil; continue }
                if !id.hasSuffix("b") { pending = (id, row[2], tournament); continue }
                defer { pending = nil }
                guard let first = pending, id == first.id + "b", first.tournament.id == tournament.id,
                      let game = game(first.html, row[2], tournament: tournament, date: date, zone: timezone) else { continue }
                result.append(game)
            }
        }
        guard datedTables > 0 else { throw SportsServiceError.invalidResponse }
        return SportsScheduleDayPolicy.canonicalGames(result)
    }

    private static func game(_ first: String, _ second: String, tournament: (id: String, title: String, doubles: Bool), date: [String], zone: TimeZone) -> SportsGame? {
        guard let detail = links(first).first(where: { $0.href.range(of: "^/match-detail/\\?id=[0-9]{1,18}$", options: .regularExpression) != nil }),
              let time = cells(first).first(where: { $0.classes.contains("time") }).map({ text($0.html.components(separatedBy: "<").first ?? "") }),
              let clock = matches("^([0-9]{1,2}):([0-9]{2})$", time).first,
              let hour = Int(clock[1]), hour < 24, let minute = Int(clock[2]), minute < 60,
              let day = Int(date[1]), let month = Int(date[2]), let year = Int(date[3]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let start = calendar.date(from: DateComponents(timeZone: zone, year: year, month: month, day: day, hour: hour, minute: minute)),
              calendar.component(.day, from: start) == day, calendar.component(.month, from: start) == month,
              let away = player(first), let home = player(second), away.id != home.id else { return nil }
        let awayResult = result(first), homeResult = result(second)
        let final = awayResult != nil && homeResult != nil
        let resultCells = (cells(first) + cells(second)).filter { $0.classes.contains("result") }
        let outcome = resultCells.map { text($0.html).lowercased() }.joined(separator: " ")
        let exceptional = outcome.contains("ret") ? "Retired" : outcome.contains("w.o") || outcome.contains("walkover") ? "Walkover" : outcome.contains("cancel") ? "Cancelled" : nil
        guard final || resultCells.isEmpty || exceptional != nil else { return nil }
        let winner = final && awayResult != homeResult ? ((awayResult ?? 0) > (homeResult ?? 0) ? away.id : home.id) : nil
        let matchID = String(detail.href.dropFirst("/match-detail/?id=".count))
        let metadata = SportsTennisMatch(tour: .challenger, tournament: tournament.title, tournamentID: tournament.id,
            discipline: tournament.doubles ? "Men's Doubles" : "Men's Singles", awaySets: sets(first), homeSets: sets(second),
            winnerID: winner, source: "tennisexplorer", competitionID: matchID)
        return SportsGame(eventID: "challenger-\(matchID)", league: .tennis, date: start,
            state: final || exceptional != nil ? "post" : "pre", status: exceptional ?? (final ? "Final" : "Scheduled"), home: home, away: away,
            venue: "", broadcasts: "", link: "https://www.tennisexplorer.com\(detail.href)", tennis: metadata)
    }

    private static func player(_ row: String) -> SportsTeam? {
        guard let cell = cells(row).first(where: { $0.classes.contains("t-name") }) else { return nil }
        let players = links(cell.html).filter { $0.href.range(of: "^/(?:player/[a-z0-9-]+|doubles-team/[a-z0-9-]+/[a-z0-9-]+)/$", options: .regularExpression) != nil }
        guard !players.isEmpty, players.count <= 2 else { return nil }
        let names = players.map { $0.title.isEmpty ? text($0.html) : text($0.title) }
        guard names.allSatisfy({ !$0.isEmpty }) else { return nil }
        return SportsTeam(id: "te:" + players.map(\.href).joined(separator: "+"), name: names.joined(separator: " / "),
            abbreviation: names.joined(separator: " / "), logo: "", score: result(row).map(String.init) ?? "")
    }
    private static func result(_ row: String) -> Int? {
        guard let value = cells(row).first(where: { $0.classes.contains("result") }).map({ text($0.html) }),
              let number = Int(value), (0...5).contains(number) else { return nil }
        return number
    }
    private static func sets(_ row: String) -> [String] {
        let values = cells(row).filter { $0.classes.contains("score") }.prefix(5).map { cell -> String in
            let raw = text(cell.html.replacingOccurrences(of: "<sup\\b[^>]*>[\\s\\S]*?</sup>", with: "", options: .regularExpression))
            guard let number = Int(raw), (0...99).contains(number) else { return "" }
            return String(number)
        }
        let end = values.lastIndex(where: { !$0.isEmpty }).map { $0 + 1 } ?? 0
        return values.prefix(end).map { $0.isEmpty ? "—" : $0 }
    }
    private static func cells(_ row: String) -> [(classes: Set<String>, html: String)] {
        matches("<td\\b([^>]*)>([\\s\\S]*?)</td>", row).map { (classes($0[1]), $0[2]) }
    }
    private static func links(_ html: String) -> [(href: String, html: String, title: String)] {
        matches("<a\\b([^>]*)>([\\s\\S]*?)</a>", html).compactMap { match in
            attribute("href", match[1]).map { (text($0), match[2], attribute("title", match[1]) ?? "") }
        }
    }
    private static func classes(_ attrs: String) -> Set<String> { Set((attribute("class", attrs) ?? "").split(whereSeparator: \.isWhitespace).map(String.init)) }
    private static func attribute(_ name: String, _ attrs: String) -> String? { matches("(?:^|\\s)\(name)\\s*=\\s*[\"']([^\"']*)[\"']", attrs).first?[1] }
    private static func text(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let text = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: text.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : text.substring(with: match.range(at: $0)) }
        }
    }
}
