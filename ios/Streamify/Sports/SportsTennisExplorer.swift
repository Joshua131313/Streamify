import Foundation

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
