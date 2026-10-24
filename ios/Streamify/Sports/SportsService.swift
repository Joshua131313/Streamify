import Foundation

/// Uses the same ESPN schedule and Streamed discovery contracts as Android.
struct SportsService: Sendable {
    var backend = ""
    var session: URLSession = .shared
    var calendar: Calendar = .current

    private func json(_ value: String) async throws -> Any {
        guard let url = sportsHTTPSURL(value) else { throw SportsServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SportsServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw SportsServiceError.unavailable(http.statusCode) }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func object(_ url: String) async throws -> [String: Any] {
        guard let result = try await json(url) as? [String: Any] else { throw SportsServiceError.invalidResponse }
        return result
    }

    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return short.date(from: value)
    }

    private func parseTeam(_ raw: [String: Any]) -> SportsTeam {
        SportsTeam(id: raw.sportsText("id"), name: raw.sportsText("displayName"), abbreviation: raw.sportsText("abbreviation"),
                   logo: raw.sportsObjects("logos").first?.sportsText("href") ?? raw.sportsText("logo"),
                   record: raw.sportsObject("record").sportsObjects("items").first?.sportsText("summary") ?? "")
    }

    func parseGame(_ raw: [String: Any], league: SportsLeague) -> SportsGame? {
        guard let competition = raw.sportsObjects("competitions").first else { return nil }
        let competitors = competition.sportsObjects("competitors")
        func side(_ name: String) -> SportsTeam? {
            guard let entry = competitors.first(where: { $0.sportsText("homeAway") == name }) else { return nil }
            let item = entry.sportsObject("team")
            var team = parseTeam(item)
            team.score = (entry["score"] as? [String: Any])?.sportsText("displayValue") ?? entry.sportsText("score")
            team.record = entry.sportsObjects("records").first?.sportsText("summary") ?? team.record
            return team
        }
        guard let home = side("home"), let away = side("away"), !home.id.isEmpty, !away.id.isEmpty else { return nil }
        let status = competition["status"] as? [String: Any] ?? raw.sportsObject("status")
        let type = status.sportsObject("type")
        let dateText = raw.sportsText("date").isEmpty ? competition.sportsText("date") : raw.sportsText("date")
        let detail = type.sportsText("shortDetail").isEmpty ? type.sportsText("description") : type.sportsText("shortDetail")
        let broadcasts = competition.sportsObjects("broadcasts").flatMap { $0["names"] as? [String] ?? [] }
        return SportsGame(eventID: raw.sportsText("id"), league: league, date: Self.parseDate(dateText), state: type.sportsText("state"),
                          status: detail, home: home, away: away, venue: competition.sportsObject("venue").sportsText("fullName"),
                          broadcasts: broadcasts.joined(separator: " · "), link: raw.sportsObjects("links").first?.sportsText("href") ?? "")
    }

    private func backendGame(_ raw: [String: Any], league: SportsLeague) -> SportsGame? {
        func side(_ key: String) -> SportsTeam {
            let team = raw.sportsObject(key)
            return SportsTeam(id: team.sportsText("id"), name: team.sportsText("name"), abbreviation: team.sportsText("abbreviation"),
                              logo: team.sportsText("logo"), score: team.sportsText("score"), record: team.sportsText("record"))
        }
        let home = side("homeTeam"), away = side("awayTeam")
        guard !home.id.isEmpty, !away.id.isEmpty else { return nil }
        return SportsGame(eventID: raw.sportsText("id"), league: league, date: Self.parseDate(raw.sportsText("date")), state: raw.sportsText("state"),
                          status: raw.sportsText("status"), home: home, away: away, venue: raw.sportsObject("venue").sportsText("name"),
                          broadcasts: (raw["broadcasts"] as? [String] ?? []).joined(separator: " · "), link: raw.sportsText("gameLink"))
    }

    func schedule(leagues: [SportsLeague], day: Date) async throws -> SportsSchedule {
        let selected = SportsLeague.allCases.filter { leagues.contains($0) }
        guard !selected.isEmpty else { return SportsSchedule(games: [], failedLeagues: [], partial: false) }
        var games: [SportsGame] = []
        var failures: [SportsLeague] = []
        var partial = false
        // At most five leagues run together, each requesting its three UTC days in order.
        try await withThrowingTaskGroup(of: LeagueScheduleResult.self) { group in
            for league in selected {
                group.addTask {
                    do {
                        let result = try await self.schedule(league: league, day: day)
                        return LeagueScheduleResult(league: league, schedule: result)
                    } catch is CancellationError { throw CancellationError() }
                    catch { try Task.checkCancellation(); return LeagueScheduleResult(league: league, schedule: nil) }
                }
            }
            for try await result in group {
                if let loaded = result.schedule { games += loaded.games; partial = partial || loaded.partial }
                else { failures.append(result.league) }
            }
        }
        guard failures.count < selected.count else { throw SportsServiceError.noSchedule }
        return SportsSchedule(games: games.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }, failedLeagues: failures, partial: partial || !failures.isEmpty)
    }

    private struct LeagueScheduleResult: Sendable {
        let league: SportsLeague
        let schedule: SportsSchedule?
    }

    private func schedule(league: SportsLeague, day: Date) async throws -> SportsSchedule {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = calendar.timeZone
        date.dateFormat = "yyyy-MM-dd"
        let base = backend.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var backendGames: [SportsGame] = []
        if !base.isEmpty {
            guard sportsHTTPSURL(base) != nil else { throw SportsServiceError.invalidURL }
            do {
                let dayText = date.string(from: day)
                let response = try await object("\(base)/api/schedule?league=\(league.rawValue)&start=\(dayText)&end=\(dayText)")
                backendGames = response.sportsObjects("games").compactMap { backendGame($0, league: league) }.filter { $0.date.map { calendar.isDate($0, inSameDayAs: day) } == true }
                if (response["failedDates"] as? [Any] ?? []).isEmpty { return SportsSchedule(games: backendGames, failedLeagues: [], partial: false) }
            } catch is CancellationError { throw CancellationError() } catch { }
        }
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.dateFormat = "yyyyMMdd"
        var games = backendGames
        var failed = 0
        // The selected local date can overlap two UTC days; include both neighbors.
        for offset in -1...1 {
            guard let target = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            do {
                let response = try await object("\(league.endpoint)/scoreboard?dates=\(utc.string(from: target))&limit=100")
                games += response.sportsObjects("events").compactMap { parseGame($0, league: league) }
            } catch is CancellationError { throw CancellationError() } catch { failed += 1 }
        }
        if failed == 3 && backendGames.isEmpty { throw SportsServiceError.noSchedule }
        var identities = Set<String>()
        return SportsSchedule(games: games.filter { game in
            game.date.map { calendar.isDate($0, inSameDayAs: day) } == true && identities.insert(game.id).inserted
        }, failedLeagues: [], partial: failed > 0)
    }

    func teams(league: SportsLeague) async throws -> [SportsTeamResult] {
        let response = try await object("\(league.endpoint)/teams?limit=1000")
        return response.sportsObjects("sports").flatMap { $0.sportsObjects("leagues") }.flatMap { $0.sportsObjects("teams") }
            .map { SportsTeamResult(league: league, team: parseTeam($0.sportsObject("team"))) }.filter { !$0.team.id.isEmpty }
    }

    func profile(_ result: SportsTeamResult) async throws -> SportsTeamProfile {
        let root = "\(result.league.endpoint)/teams/\(result.team.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        let information = (try await object(root)).sportsObject("team")
        let schedule = try? await object(root + "/schedule")
        try Task.checkCancellation()
        let roster = try? await object(root + "/roster")
        try Task.checkCancellation()
        let athletes = (roster?.sportsObjects("athletes") ?? []).flatMap { group in group["items"] == nil ? [group] : group.sportsObjects("items") }
        return SportsTeamProfile(team: parseTeam(information), location: information.sportsText("location"),
                                 venue: information.sportsObject("franchise").sportsObject("venue").sportsText("fullName"),
                                 games: (schedule?.sportsObjects("events") ?? []).compactMap { parseGame($0, league: result.league) }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) },
                                 roster: athletes.enumerated().map { index, player in
            let athlete = player.sportsObject("athlete")
            let photo = [player.sportsObject("headshot").sportsText("href"), player.sportsText("headshot"),
                         athlete.sportsObject("headshot").sportsText("href"), athlete.sportsText("headshot")]
                .compactMap(sportsHTTPSURL).first?.absoluteString ?? ""
            return SportsRosterPlayer(id: player.sportsText("id").isEmpty ? String(index) : player.sportsText("id"), name: player.sportsText("displayName"), number: player.sportsText("jersey"), position: player.sportsObject("position").sportsText("abbreviation"), height: player.sportsText("displayHeight"), photo: photo)
        }, scheduleUnavailable: schedule == nil, rosterUnavailable: roster == nil)
    }

    func center(_ game: SportsGame) async throws -> SportsGameCenter {
        let response = try await object("\(game.league.endpoint)/summary?event=\(game.eventID)")
        let header = response.sportsObject("header")
        let fresh = parseGame(header, league: game.league) ?? game
        let competitors = header.sportsObjects("competitions").first?.sportsObjects("competitors") ?? []
        let awayPeriods = competitors.first { $0.sportsText("homeAway") == "away" }?.sportsObjects("linescores") ?? []
        let homePeriods = competitors.first { $0.sportsText("homeAway") == "home" }?.sportsObjects("linescores") ?? []
        func score(_ values: [[String: Any]], index: Int) -> String {
            guard values.indices.contains(index) else { return "—" }
            let item = values[index]
            return item.sportsText("displayValue").isEmpty ? item.sportsText("value") : item.sportsText("displayValue")
        }
        let scoring = (0..<max(awayPeriods.count, homePeriods.count)).map { index in
            SportsStatRow(id: String(index), label: "\(game.league == .mlb ? "Inning" : "Period") \(index + 1)", away: score(awayPeriods, index: index), home: score(homePeriods, index: index))
        }
        let teams = response.sportsObject("boxscore").sportsObjects("teams")
        let away = teams.first { $0.sportsObject("team").sportsText("id") == game.away.id }?.sportsObjects("statistics") ?? []
        let home = teams.first { $0.sportsObject("team").sportsText("id") == game.home.id }?.sportsObjects("statistics") ?? []
        let keys = Array(Set((away + home).map { $0.sportsText("name") })).sorted()
        let statistics = keys.map { key -> SportsStatRow in
            let a = away.first { $0.sportsText("name") == key }, h = home.first { $0.sportsText("name") == key }
            return SportsStatRow(id: key, label: (a ?? h ?? [:]).sportsText("label"), away: a?.sportsText("displayValue") ?? "—", home: h?.sportsText("displayValue") ?? "—")
        }
        let latest = response.sportsObjects("plays").last?.sportsText("text") ?? response.sportsObject("drives").sportsObject("current").sportsObjects("plays").last?.sportsText("text") ?? ""
        return SportsGameCenter(game: fresh, scoring: scoring, statistics: statistics, latest: latest)
    }

    func streams(_ game: SportsGame) async throws -> [SportsStream] {
        guard game.canWatch else { return [] }
        guard let matches = try await json("https://streamed.pk/api/matches/all") as? [[String: Any]] else { throw SportsServiceError.invalidResponse }
        guard let match = Self.matchingStreamMatch(matches, game: game) else { return [] }
        var streams: [SportsStream] = []
        var failures = 0
        let sources = Array(match.sportsObjects("sources").prefix(8))
        for source in sources {
            let name = source.sportsText("source").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let id = source.sportsText("id").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            do {
                let response = try await json("https://streamed.pk/api/stream/\(name)/\(id)") as? [[String: Any]] ?? []
                streams += response.compactMap { item in
                    guard let url = sportsHTTPSURL(item.sportsText("embedUrl")) else { return nil }
                    return SportsStream(title: "\(source.sportsText("source")) \(item.sportsText("streamNo")) · \(item.sportsText("language"))\((item["hd"] as? Bool) == true ? " · HD" : "")", url: url)
                }
            } catch is CancellationError { throw CancellationError() } catch { failures += 1 }
        }
        if failures == sources.count && !sources.isEmpty { throw SportsServiceError.streamsUnavailable }
        var seen = Set<URL>()
        return streams.filter { seen.insert($0.url).inserted }
    }

    /// Exact full-team matching prevents an unrelated game from being offered as a source.
    static func matchingStreamMatch(_ matches: [[String: Any]], game: SportsGame, now: Date = Date()) -> [String: Any]? {
        func normalized(_ value: String) -> String {
            value.lowercased().replacingOccurrences(of: "st. louis", with: "saint louis").replacingOccurrences(of: "st louis", with: "saint louis")
                .replacingOccurrences(of: "\\bla\\b", with: "los angeles", options: .regularExpression).filter { $0.isLetter || $0.isNumber }
        }
        let homeName = normalized(game.home.name), awayName = normalized(game.away.name)
        guard !homeName.isEmpty, !awayName.isEmpty else { return nil }
        let match = matches.filter { item in
            let date = (item["date"] as? NSNumber)?.doubleValue ?? 0
            let teams = item.sportsObject("teams")
            let names = [normalized(teams.sportsObject("home").sportsText("name")), normalized(teams.sportsObject("away").sportsText("name"))]
            let title = normalized(item.sportsText("title"))
            return item.sportsText("category") == game.league.category && !item.sportsObjects("sources").isEmpty &&
                (date == 1 || abs(date / 1000 - now.timeIntervalSince1970) <= 18 * 3600) &&
                ((names.contains(homeName) && names.contains(awayName)) || (title.contains(homeName) && title.contains(awayName)))
        }.min { abs((($0["date"] as? NSNumber)?.doubleValue ?? 0) / 1000 - now.timeIntervalSince1970) < abs((($1["date"] as? NSNumber)?.doubleValue ?? 0) / 1000 - now.timeIntervalSince1970) }
        return match
    }
}
