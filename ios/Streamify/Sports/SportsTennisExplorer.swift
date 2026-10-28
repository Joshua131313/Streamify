import Foundation

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
                      let start = match["startTimestamp"] as? NSNumber, start.doubleValue > 0,
                      let route = historyURL(match.sportsText("url")),
                      let a = player(players[0], tour: tour), let b = player(players[1], tour: tour), a.id != b.id else { return nil }
                let tournament = group.sportsText("tournamentId")
                guard tournament.range(of: "^[0-9]{1,18}$", options: .regularExpression) != nil else { return nil }
                var metadata = SportsTennisMatch(tour: tour == "wta" ? .wta : path.contains("challenger") || group["rank"] as? Int == 1 ? .challenger : .atp,
                    tournament: group.sportsText("name").replacingOccurrences(of: "^(ATP|WTA) ", with: "", options: .regularExpression),
                    tournamentID: "tl-\(tour)-\(tournament)", discipline: match["doubles"] as? Bool == true ? "Doubles" : "Singles",
                    awaySets: sets(players[0]), homeSets: sets(players[1]), source: "tennislive", historyURL: route)
                let point = match["points"] as? [String] ?? []
                if state == "in" {
                    metadata.awayPoint = point.indices.contains(0) ? point[0] : nil
                    metadata.homePoint = point.indices.contains(1) ? point[1] : nil
                    if let index = match["server"] as? Int, [0, 1].contains(index) { metadata.servingID = index == 0 ? a.id : b.id }
                }
                if state == "post", let winner = match["winnerId"] as? NSNumber {
                    metadata.winnerID = players[0].sportsText("id") == winner.stringValue ? a.id : players[1].sportsText("id") == winner.stringValue ? b.id : nil
                }
                return SportsGame(eventID: "tennislive-\(tour)-\(tournament)-\(players[0].sportsText("id"))-\(players[1].sportsText("id"))",
                    league: .tennis, date: Date(timeIntervalSince1970: start.doubleValue), state: state,
                    status: state == "post" ? "Final" : state == "in" ? match.sportsText("setLabel") : "Scheduled",
                    home: b, away: a, venue: "", broadcasts: "", link: route, tennis: metadata)
            }
        }
    }

    static func merge(_ scheduled: [SportsGame], live: [SportsGame]) -> [SportsGame] {
        var result = SportsScheduleDayPolicy.canonicalGames(scheduled)
        for snapshot in SportsScheduleDayPolicy.canonicalGames(live) {
            let candidates = result.indices.filter { sameMatch(result[$0], snapshot) }
            guard candidates.count == 1, let index = candidates.first else {
                if candidates.isEmpty { result.append(snapshot) }; continue
            }
            let original = result[index]
            guard var metadata = original.tennis, let fresh = snapshot.tennis else { continue }
            let aligned = samePlayer(original.away.name, snapshot.away.name)
            let away = aligned ? snapshot.away : snapshot.home, home = aligned ? snapshot.home : snapshot.away
            metadata.awaySets = aligned ? fresh.awaySets : fresh.homeSets
            metadata.homeSets = aligned ? fresh.homeSets : fresh.awaySets
            metadata.awayPoint = aligned ? fresh.awayPoint : fresh.homePoint
            metadata.homePoint = aligned ? fresh.homePoint : fresh.awayPoint
            metadata.servingID = fresh.servingID == away.id ? original.away.id : fresh.servingID == home.id ? original.home.id : nil
            metadata.winnerID = fresh.winnerID == away.id ? original.away.id : fresh.winnerID == home.id ? original.home.id : nil
            metadata.historyURL = fresh.historyURL
            var a = original.away, b = original.home
            a.score = away.score; b.score = home.score
            // Preserve the ESPN/Challenger identity used by tracking and sources.
            result[index] = SportsGame(eventID: original.eventID, league: .tennis, date: original.date ?? snapshot.date,
                state: snapshot.state, status: snapshot.status, home: b, away: a, venue: original.venue,
                broadcasts: original.broadcasts, link: original.link, tennis: metadata)
        }
        return SportsScheduleDayPolicy.canonicalGames(result)
    }

    static func sameMatch(_ a: SportsGame, _ b: SportsGame) -> Bool {
        guard let at = a.tennis, let bt = b.tennis, at.isDoubles == bt.isDoubles,
              let ad = a.date, let bd = b.date, abs(ad.timeIntervalSince(bd)) < 18 * 3600,
              tournament(at.tournament) == tournament(bt.tournament) else { return false }
        return (samePlayer(a.away.name, b.away.name) && samePlayer(a.home.name, b.home.name)) ||
            (samePlayer(a.away.name, b.home.name) && samePlayer(a.home.name, b.away.name))
    }

    static func samePlayer(_ a: String, _ b: String) -> Bool {
        let x = words(a), y = words(b)
        if x == y { return !x.isEmpty }
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
        return words(value).filter { !["atp", "wta", "challenger", "open", "tennis", "125"].contains($0) && seen.insert($0).inserted }.joined()
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
