import Foundation
import CoreFoundation

/// Today includes games still in progress from the preceding local date.
/// Resolve duplicate states before date filtering so a stale live copy cannot
/// bring a game back after another response has already reported it final.
enum SportsScheduleDayPolicy {
    static func canonicalGames(_ games: [SportsGame]) -> [SportsGame] {
        var latest: [String: SportsGame] = [:]
        for game in games {
            if let previous = latest[game.id], phase(previous) > phase(game) { continue }
            latest[game.id] = game
        }
        return latest.values.sorted {
            if $0.date != $1.date { return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            return $0.id < $1.id
        }
    }

    static func games(_ games: [SportsGame], for day: Date, now: Date, calendar: Calendar) -> [SportsGame] {
        canonicalGames(games).filter { includes($0, on: day, now: now, calendar: calendar) }
    }

    static func includes(_ game: SportsGame, on day: Date, now: Date, calendar: Calendar) -> Bool {
        guard let start = game.date else { return false }
        if calendar.isDate(start, inSameDayAs: day) { return true }
        let today = calendar.startOfDay(for: now)
        guard calendar.isDate(day, inSameDayAs: today), game.isLive,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return false }
        return start >= yesterday && start < today
    }

    static func markerDay(for game: SportsGame, now: Date, calendar: Calendar) -> Date? {
        guard let start = game.date else { return nil }
        let today = calendar.startOfDay(for: now)
        return start < today && includes(game, on: today, now: now, calendar: calendar) ? today : calendar.startOfDay(for: start)
    }

    static func selectedDay(_ selection: Date, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.date(byAdding: .day, value: 13, to: today) ?? today
        return min(lastDay, max(today, calendar.startOfDay(for: selection)))
    }

    private static func phase(_ game: SportsGame) -> Int {
        game.isFinal ? 2 : game.isLive ? 1 : 0
    }
}

/// Uses the same ESPN schedule and Streamed discovery contracts as Android.
struct SportsService: Sendable {
    var backend = ""
    var session: URLSession = .shared
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }
    var forceReload = false

    private func json(_ value: String) async throws -> Any {
        guard let url = sportsHTTPSURL(value) else { throw SportsServiceError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Streamify/1.1", forHTTPHeaderField: "User-Agent")
        let prepared = request
        let lifetime: TimeInterval = url.path.hasSuffix("/teams") || url.path.hasSuffix("/roster") ? 3600 : 30
        let fetch: @Sendable () async throws -> Data = {
                let (data, response) = try await session.data(for: prepared)
                guard let http = response as? HTTPURLResponse else { throw SportsServiceError.invalidResponse }
                guard (200...299).contains(http.statusCode) else { throw SportsServiceError.unavailable(http.statusCode) }
                _ = try JSONSerialization.jsonObject(with: data)
                return data
            }
        let data: Data
        if url.host == "streamed.pk", url.path.hasPrefix("/api/stream/") {
            // Source addresses can expire or depend on the current connection.
            // Resolve each Watch afresh even when browsing data stays warm.
            data = try await fetch()
        } else {
            data = try await ResponseMemoryCache.shared.data(key: ResponseMemoryCache.key(for: prepared, session: session),
                lifetime: lifetime, reload: forceReload, operation: fetch)
        }
        try Task.checkCancellation()
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
                   record: raw.sportsObject("record").sportsObjects("items").first?.sportsText("summary") ?? "",
                   streamNames: [raw.sportsText("displayName"), raw.sportsText("shortDisplayName"), raw.sportsText("location")].filter { !$0.isEmpty },
                   primaryColorHex: Self.teamColor(raw.sportsText("color")))
    }

    static func teamColor(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return nil }
        return hex.uppercased()
    }

    func parseGame(_ raw: [String: Any], league: SportsLeague, situationOverride: [String: Any]? = nil) -> SportsGame? {
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
        var situation = competition.sportsObject("situation")
            .merging(raw.sportsObject("situation")) { _, latest in latest }
            .merging(situationOverride ?? [:]) { _, latest in latest }
        // ESPN summary headers can publish a possession flag per competitor.
        // Both false (or both true), and explicitly unsupported arrows, are unknown.
        let possessing = competitors.filter { Self.explicitBool($0["possession"]) == true }
        if ["football", "basketball"].contains(league.sport), possessing.count == 1,
           Self.explicitBool(competition["possessionArrowAvailable"]) != false {
            situation["competitorPossessionTeamID"] = possessing[0].sportsObject("team").sportsText("id")
        }
        return SportsGame(eventID: raw.sportsText("id"), league: league, date: Self.parseDate(dateText), state: type.sportsText("state"),
                          status: detail, home: home, away: away, venue: competition.sportsObject("venue").sportsText("fullName"),
                          broadcasts: broadcasts.joined(separator: " · "), link: raw.sportsObjects("links").first?.sportsText("href") ?? "",
                          liveSituation: Self.liveSituation(situation, status: status, state: type.sportsText("state"), league: league, home: home, away: away))
    }

    static func liveSituation(_ raw: [String: Any], status: [String: Any], state: String,
                              league: SportsLeague, home: SportsTeam, away: SportsTeam) -> SportsLiveSituation? {
        guard state == "in" else { return nil }
        let period = Int(status.sportsText("period")).flatMap { (1...30).contains($0) ? $0 : nil }
        let rawClock = status.sportsText("displayClock").trimmingCharacters(in: .whitespacesAndNewlines)
        let clock = league == .mlb || rawClock.range(of: #"^(?:[0-9]{1,2}:[0-5][0-9](?:\.[0-9]{1,2})?|[0-9]{1,2}(?:\.[0-9]{1,2})?)$"#, options: .regularExpression) == nil ? nil : rawClock
        let possessionObject = raw.sportsObject("possession")
        let possessionCandidates = [raw.sportsText("possession"), possessionObject.sportsText("id"),
            possessionObject.sportsObject("team").sportsText("id"), raw.sportsText("possessionTeamId"),
            raw.sportsText("possessionTeamID"), raw.sportsText("competitorPossessionTeamID"),
            possessionReference(possessionObject.sportsText("$ref"), league: league) ?? "",
            possessionReference(possessionObject.sportsObject("team").sportsText("$ref"), league: league) ?? ""]
        let validPossession = Set(possessionCandidates.filter { !$0.isEmpty && ($0 == home.id || $0 == away.id) })
        let possession = ["football", "basketball"].contains(league.sport) && validPossession.count == 1 ? validPossession.first : nil
        var result = SportsLiveSituation(period: period, clock: clock, possessionTeamID: possession)
        if league == .nfl || league == .ncaaf {
            let short = raw.sportsText("shortDownDistanceText").trimmingCharacters(in: .whitespacesAndNewlines)
            let long = raw.sportsText("downDistanceText").components(separatedBy: " at ").first ?? ""
            let down = (short.isEmpty ? long : short).trimmingCharacters(in: .whitespacesAndNewlines)
            if !down.isEmpty && down.count <= 48 { result.downDistance = down }
            let field = raw.sportsText("possessionText").trimmingCharacters(in: .whitespacesAndNewlines)
            if let position = footballPosition(field, possession: possession, home: home, away: away) {
                result.fieldPosition = field
                result.fieldProgress = position.progress
            }
        }
        if league == .mlb {
            let halfText = status.sportsText("periodPrefix").lowercased()
            let half: SportsInningHalf? = ["top": .top, "bottom": .bottom, "middle": .middle, "mid": .middle, "end": .end][halfText]
            let baseball = SportsBaseballSituation(firstOccupied: baseOccupied(raw["onFirst"]),
                secondOccupied: baseOccupied(raw["onSecond"]), thirdOccupied: baseOccupied(raw["onThird"]),
                balls: count(raw["balls"], range: 0...4), strikes: count(raw["strikes"], range: 0...3),
                outs: count(raw["outs"], range: 0...3), inning: period, half: half)
            if baseball.hasBaseData || baseball.balls != nil || baseball.strikes != nil || baseball.outs != nil || baseball.inning != nil || baseball.half != nil {
                result.baseball = baseball
            }
        }
        return result.period == nil && result.clock == nil && result.possessionTeamID == nil &&
            result.downDistance == nil && result.fieldPosition == nil && result.baseball == nil ? nil : result
    }

    private static func explicitBool(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func possessionReference(_ value: String, league: SportsLeague) -> String? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.lowercased() == "sports.core.api.espn.com", url.user == nil, url.password == nil,
              url.port == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 7, Array(parts.prefix(6)) == ["v2", "sports", league.sport, "leagues", league.rawValue, "teams"],
              validEventID(parts[6]) else { return nil }
        return parts[6]
    }
    private static func count(_ raw: Any?, range: ClosedRange<Int>) -> Int? {
        guard explicitBool(raw) == nil else { return nil }
        let value: Int?
        if let number = raw as? NSNumber, number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
           number.doubleValue >= Double(range.lowerBound), number.doubleValue <= Double(range.upperBound) { value = number.intValue }
        else if let text = raw as? String { value = Int(text) }
        else { value = nil }
        return value.flatMap { range.contains($0) ? $0 : nil }
    }
    private static func baseOccupied(_ raw: Any?) -> Bool? {
        if let flag = explicitBool(raw) { return flag }
        guard let player = raw as? [String: Any] else { return nil }
        let athlete = player.sportsObject("athlete")
        let identifiers = [player.sportsText("playerId"), player.sportsText("id"), athlete.sportsText("id")]
        if identifiers.contains(where: { validEventID($0) && $0.contains(where: { $0 != "0" }) }) { return true }
        // ESPN Core represents an occupied base with an athlete reference.
        if let url = URL(string: athlete.sportsText("$ref")), url.host == "sports.core.api.espn.com",
           url.path.contains("/athletes/"), validEventID(url.lastPathComponent) { return true }
        return nil
    }

    /// ESPN's `possessionText` explicitly identifies the side of midfield. Its
    /// unqualified `yardLine` can use the home team's coordinate system, so it
    /// must not be treated as offense-relative progress or guessed from score.
    private static func footballPosition(_ text: String, possession: String?, home: SportsTeam, away: SportsTeam) -> (progress: Double?, yards: Int)? {
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        guard let final = parts.last, let yards = Int(final), (0...50).contains(yards) else { return nil }
        if parts.count == 1 {
            return yards == 50 ? (possession == nil ? nil : 0.5, yards) : nil
        }
        let abbreviation = parts.dropLast().joined(separator: " ").uppercased()
        let teams = [home, away].filter { !$0.abbreviation.isEmpty && $0.abbreviation.uppercased() == abbreviation }
        guard teams.count == 1, let side = teams.first else { return nil }
        guard let possession else { return (nil, yards) }
        return (Double(side.id == possession ? yards : 100 - yards) / 100, yards)
    }

    private func backendGame(_ raw: [String: Any], league: SportsLeague) -> SportsGame? {
        func side(_ key: String) -> SportsTeam {
            let team = raw.sportsObject(key)
            return SportsTeam(id: team.sportsText("id"), name: team.sportsText("name"), abbreviation: team.sportsText("abbreviation"),
                              logo: team.sportsText("logo"), score: team.sportsText("score"), record: team.sportsText("record"),
                              primaryColorHex: Self.teamColor(team.sportsText("color")))
        }
        let home = side("homeTeam"), away = side("awayTeam")
        guard !home.id.isEmpty, !away.id.isEmpty else { return nil }
        var situation = raw.sportsObject("live")
        if situation["shortDownDistanceText"] == nil { situation["shortDownDistanceText"] = situation["downDistance"] }
        let status: [String: Any] = ["period": raw.sportsObject("period")["current"] ?? raw["period"] ?? NSNull(),
                                     "displayClock": raw["clock"] ?? NSNull()]
        return SportsGame(eventID: raw.sportsText("id"), league: league, date: Self.parseDate(raw.sportsText("date")), state: raw.sportsText("state"),
                          status: raw.sportsText("status"), home: home, away: away, venue: raw.sportsObject("venue").sportsText("name"),
                          broadcasts: (raw["broadcasts"] as? [String] ?? []).joined(separator: " · "), link: raw.sportsText("gameLink"),
                          liveSituation: Self.liveSituation(situation, status: status, state: raw.sportsText("state"), league: league, home: home, away: away))
    }

    func schedule(leagues: [SportsLeague], day: Date) async throws -> SportsSchedule {
        let referenceTime = now()
        let selectedDay = calendar.startOfDay(for: day)
        let selected = SportsLeague.allCases.filter { leagues.contains($0) }
        guard !selected.isEmpty else { return SportsSchedule(games: [], failedLeagues: [], partial: false) }
        var games: [SportsGame] = []
        var failures: [SportsLeague] = []
        var partial = false
        // Each league requests its adjacent UTC days in order.
        try await withThrowingTaskGroup(of: LeagueScheduleResult.self) { group in
            for league in selected {
                group.addTask {
                    do {
                        let result = try await self.schedule(league: league, day: selectedDay, now: referenceTime)
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

    /// The schedule is displayed first. This optional second phase adds current
    /// possession data that the legacy backend omits, without clearing cards or
    /// turning a valid scoreboard into an error when an enrichment feed fails.
    func enrichLiveGames(_ games: [SportsGame], day: Date) async -> [SportsGame] {
        let supported = Set(SportsLeague.allCases.filter { ["football", "basketball", "baseball"].contains($0.sport) })
        let missing = games.filter {
            $0.isLive && supported.contains($0.league) &&
            ($0.home.primaryColorHex == nil || $0.away.primaryColorHex == nil ||
             ($0.league == .mlb ? $0.liveSituation?.baseball?.hasBaseData != true : $0.possessionTeam == nil))
        }
        guard !Task.isCancelled else { return games }
        if missing.isEmpty { return await enrichHockey(games) }
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.dateFormat = "yyyyMMdd"
        var jobs: [(league: SportsLeague, date: String, parameters: String)] = []
        for league in SportsLeague.allCases where supported.contains(league) {
            let days = Set(missing.filter { $0.league == league }.compactMap(\.date).map { utc.string(from: $0) })
            for date in days.sorted() {
                for parameters in league.scoreboardParameters { jobs.append((league, date, parameters)) }
            }
        }
        let requests = jobs
        // At most three ESPN requests at once, independent of the live card count.
        let snapshots = await withTaskGroup(of: [SportsGame].self) { group in
            for worker in 0..<min(3, requests.count) {
                group.addTask {
                    var result: [SportsGame] = []
                    for index in stride(from: worker, to: requests.count, by: 3) {
                        guard !Task.isCancelled else { break }
                        let job = requests[index]
                        do {
                            let response = try await object("\(job.league.endpoint)/scoreboard?dates=\(job.date)\(job.parameters)")
                            result += response.sportsObjects("events").compactMap { parseGame($0, league: job.league) }
                        } catch { /* The visible base schedule remains useful. */ }
                    }
                    return result
                }
            }
            var result: [SportsGame] = []
            for await batch in group { result += batch }
            return result
        }
        guard !Task.isCancelled else { return games }
        var enriched = Self.applyingLiveSnapshots(snapshots, to: games)
        // Basketball feeds may supply possession only on their game summary.
        // Never infer it from lastPlay.team, which can name a scorer or defender.
        let summaryGames = enriched.filter { $0.isLive &&
            (($0.league.sport == "basketball" && $0.possessionTeam == nil) ||
             ($0.league == .mlb && $0.liveSituation?.baseball?.hasBaseData != true)) }
        let summaries = await withTaskGroup(of: [SportsGame].self) { group in
            for worker in 0..<min(3, summaryGames.count) {
                group.addTask {
                    var result: [SportsGame] = []
                    for index in stride(from: worker, to: summaryGames.count, by: 3) {
                        guard !Task.isCancelled else { break }
                        let game = summaryGames[index]
                        var allowed = CharacterSet.urlQueryAllowed
                        allowed.remove(charactersIn: "&+=?#")
                        guard let event = game.eventID.addingPercentEncoding(withAllowedCharacters: allowed) else { continue }
                        do {
                            let response = try await object("\(game.league.endpoint)/summary?event=\(event)")
                            if let snapshot = await summaryGame(response, fallback: game) { result.append(snapshot) }
                        } catch { /* Unknown possession stays hidden. */ }
                    }
                    return result
                }
            }
            var result: [SportsGame] = []
            for await batch in group { result += batch }
            return result
        }
        guard !Task.isCancelled else { return games }
        enriched = Self.applyingLiveSnapshots(summaries, to: enriched)
        enriched = await enrichHockey(enriched)
        return SportsScheduleDayPolicy.games(enriched, for: day, now: now(), calendar: calendar)
    }

    private func enrichHockey(_ games: [SportsGame]) async -> [SportsGame] {
        let live = games.filter { $0.league == .nhl && $0.isLive }
        guard !live.isEmpty, !Task.isCancelled else { return games }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(live.compactMap(\.date).map { formatter.string(from: $0) })
        var official: [[String: Any]] = []
        for date in dates.sorted() {
            guard !Task.isCancelled else { return games }
            if let response = try? await object("https://api-web.nhle.com/v1/score/\(date)") {
                official += response.sportsObjects("games")
            }
        }
        return games.map { game in
            guard game.league == .nhl, game.isLive,
                  let match = official.first(where: { Self.matchesHockey($0, game: game) }) else { return game }
            var updated = game
            var live = updated.liveSituation ?? SportsLiveSituation()
            live.hockey = Self.hockeySituation(match, game: game, observedAt: now())
            updated.liveSituation = live
            return updated
        }
    }

    static func matchesHockey(_ raw: [String: Any], game: SportsGame) -> Bool {
        func normalized(_ value: String) -> String {
            let upper = value.uppercased()
            return ["LA": "LAK", "NJ": "NJD", "SJ": "SJS", "TB": "TBL", "MON": "MTL", "UTAH": "UTA"][upper] ?? upper
        }
        guard game.league == .nhl, !game.away.abbreviation.isEmpty, !game.home.abbreviation.isEmpty,
              normalized(raw.sportsObject("awayTeam").sportsText("abbrev")) == normalized(game.away.abbreviation),
              normalized(raw.sportsObject("homeTeam").sportsText("abbrev")) == normalized(game.home.abbreviation),
              let start = parseDate(raw.sportsText("startTimeUTC")), let date = game.date,
              abs(start.timeIntervalSince(date)) < 6 * 3600 else { return false }
        return ["LIVE", "CRIT"].contains(raw.sportsText("gameState"))
    }

    static func hockeySituation(_ raw: [String: Any], game: SportsGame, observedAt: Date) -> SportsHockeySituation? {
        guard game.league == .nhl, game.isLive, matchesHockey(raw, game: game) else { return nil }
        let situation = raw.sportsObject("situation")
        let away = situation.sportsObject("awayTeam"), home = situation.sportsObject("homeTeam")
        let code = Array(raw.sportsText("situationCode"))
        let validCode = code.count == 4 && code.allSatisfy(\.isNumber)
        let awaySkaters = count(away["strength"], range: 3...6) ?? (validCode ? Int(String(code[1])) : nil)
        let homeSkaters = count(home["strength"], range: 3...6) ?? (validCode ? Int(String(code[2])) : nil)
        guard let awaySkaters, let homeSkaters, (3...6).contains(awaySkaters), (3...6).contains(homeSkaters) else { return nil }
        let awayTags = Set((away["situationDescriptions"] as? [String] ?? []).map { $0.uppercased() })
        let homeTags = Set((home["situationDescriptions"] as? [String] ?? []).map { $0.uppercased() })
        var empty = Set<String>()
        if awayTags.contains("EN") || (validCode && code[0] == "0") { empty.insert(game.away.id) }
        if homeTags.contains("EN") || (validCode && code[3] == "0") { empty.insert(game.home.id) }
        let ppTeams = [(game.away.id, awayTags), (game.home.id, homeTags)].filter { $0.1.contains("PP") }.map(\.0)
        let pp = ppTeams.count == 1 ? ppTeams[0] : nil
        let timer = situation.sportsText("timeRemaining")
        let time = timer.range(of: #"^[0-9]{1,2}:[0-5][0-9]$"#, options: .regularExpression) == nil ? nil : timer
        return SportsHockeySituation(awaySkaters: awaySkaters, homeSkaters: homeSkaters,
            powerPlayTeamID: pp, emptyNetTeamIDs: empty, strengthTime: time, observedAt: observedAt)
    }

    static func applyingLiveSnapshots(_ snapshots: [SportsGame], to games: [SportsGame]) -> [SportsGame] {
        let freshest = Dictionary(uniqueKeysWithValues: SportsScheduleDayPolicy.canonicalGames(snapshots).map { ($0.id, $0) })
        return games.map { game in
            // A result can advance a live game to Final, but cannot revive a
            // final card or attach a different matchup's possession snapshot.
            guard game.isLive, let next = freshest[game.id], next.state != "pre",
                  next.home.id == game.home.id, next.away.id == game.away.id else { return game }
            return preservingPresentation(next, from: game)
        }
    }

    private static func preservingPresentation(_ next: SportsGame, from game: SportsGame) -> SportsGame {
        func team(_ next: SportsTeam, _ previous: SportsTeam) -> SportsTeam {
            SportsTeam(id: next.id, name: next.name.isEmpty ? previous.name : next.name,
                abbreviation: next.abbreviation.isEmpty ? previous.abbreviation : next.abbreviation,
                logo: next.logo.isEmpty ? previous.logo : next.logo, score: next.score, record: next.record.isEmpty ? previous.record : next.record,
                streamNames: next.streamNames.isEmpty ? previous.streamNames : next.streamNames,
                primaryColorHex: next.primaryColorHex ?? previous.primaryColorHex)
        }
        return SportsGame(eventID: next.eventID, league: next.league, date: next.date ?? game.date,
            state: next.state, status: next.status, home: team(next.home, game.home), away: team(next.away, game.away),
            venue: next.venue.isEmpty ? game.venue : next.venue, broadcasts: next.broadcasts.isEmpty ? game.broadcasts : next.broadcasts,
            link: next.link.isEmpty ? game.link : next.link, liveSituation: next.liveSituation)
    }

    private func summaryGame(_ response: [String: Any], fallback game: SportsGame) async -> SportsGame? {
        let header = response.sportsObject("header")
        var situation = response.sportsObject("situation")
        guard var fresh = parseGame(header, league: game.league, situationOverride: situation),
              fresh.eventID == game.eventID, fresh.home.id == game.home.id, fresh.away.id == game.away.id else { return nil }
        if fresh.isLive, game.league.sport == "basketball", fresh.possessionTeam == nil, Self.validEventID(game.eventID) {
            // Some feeds expose the explicit possession only on the core
            // situation. A last play's team is never treated as possession.
            let url = "https://sports.core.api.espn.com/v2/sports/basketball/leagues/\(game.league.rawValue)/events/\(game.eventID)/competitions/\(game.eventID)/situation"
            if let core = try? await object(url), !Task.isCancelled {
                situation.merge(core) { _, current in current }
                fresh = parseGame(header, league: game.league, situationOverride: situation) ?? fresh
            }
        }
        if fresh.isLive, game.league == .mlb, fresh.liveSituation?.baseball?.hasBaseData != true, Self.validEventID(game.eventID) {
            let url = "https://sports.core.api.espn.com/v2/sports/baseball/leagues/mlb/events/\(game.eventID)/competitions/\(game.eventID)/situation"
            if let core = try? await object(url), !Task.isCancelled {
                situation.merge(core) { _, current in current }
                fresh = parseGame(header, league: game.league, situationOverride: situation) ?? fresh
            }
        }
        return Self.preservingPresentation(fresh, from: game)
    }

    private func schedule(league: SportsLeague, day: Date, now: Date) async throws -> SportsSchedule {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = calendar.timeZone
        date.dateFormat = "yyyy-MM-dd"
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.dateFormat = "yyyy-MM-dd"
        let base = backend.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var backendGames: [SportsGame] = []
        if !base.isEmpty && league != .ncaaf {
            guard sportsHTTPSURL(base) != nil else { throw SportsServiceError.invalidURL }
            do {
                let dayText = date.string(from: day)
                let firstDay = calendar.isDate(day, inSameDayAs: now) ? calendar.date(byAdding: .day, value: -1, to: day) ?? day : day
                var backendCalendar = Calendar(identifier: .gregorian)
                backendCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let minimumDay = backendCalendar.date(byAdding: .day, value: -1, to: now) ?? now
                // The backend accepts UTC yesterday onward and already returns
                // adjacent UTC feeds. Reuse those feeds, expanding the range only
                // when the previous local day starts an additional UTC day back.
                let requiredStart = backendCalendar.date(byAdding: .day, value: 1, to: backendCalendar.startOfDay(for: firstDay)) ?? firstDay
                let firstDayText = max(min(dayText, utc.string(from: requiredStart)), utc.string(from: minimumDay))
                let response = try await object("\(base)/api/schedule?league=\(league.rawValue)&start=\(firstDayText)&end=\(dayText)")
                backendGames = response.sportsObjects("games").compactMap { backendGame($0, league: league) }
                if (response["failedDates"] as? [Any] ?? []).isEmpty {
                    return SportsSchedule(games: SportsScheduleDayPolicy.games(backendGames, for: day, now: now, calendar: calendar), failedLeagues: [], partial: false)
                }
            } catch is CancellationError { throw CancellationError() } catch { }
        }
        utc.dateFormat = "yyyyMMdd"
        var games = backendGames
        var failed = 0
        var attempted = 0
        // The selected local date can overlap two UTC days; include both neighbors.
        for offset in -1...1 {
            guard let target = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            for parameters in league.scoreboardParameters {
                attempted += 1
                do {
                    let response = try await object("\(league.endpoint)/scoreboard?dates=\(utc.string(from: target))\(parameters)")
                    games += response.sportsObjects("events").compactMap { parseGame($0, league: league) }
                } catch is CancellationError { throw CancellationError() } catch { failed += 1 }
            }
        }
        if failed == attempted && backendGames.isEmpty { throw SportsServiceError.noSchedule }
        return SportsSchedule(games: SportsScheduleDayPolicy.games(games, for: day, now: now, calendar: calendar), failedLeagues: [], partial: failed > 0)
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
        let roster = try? await object(root + "/roster" + (result.league == .ncaaf ? "?limit=1000" : ""))
        try Task.checkCancellation()
        let athletes = (roster?.sportsObjects("athletes") ?? []).flatMap { group in group["items"] == nil ? [group] : group.sportsObjects("items") }
        let scheduledGames = (schedule?.sportsObjects("events") ?? []).compactMap { parseGame($0, league: result.league) }
        let liveScores = await withTaskGroup(of: SportsGame?.self) { group in
            for game in scheduledGames where game.isLive {
                group.addTask { try? await center(game).game }
            }
            var values: [SportsGame] = []
            for await value in group { if let value { values.append(value) } }
            return values
        }
        return SportsTeamProfile(team: parseTeam(information), location: information.sportsText("location"),
                                 venue: information.sportsObject("franchise").sportsObject("venue").sportsText("fullName"),
                                 games: Self.applyingLiveSnapshots(liveScores, to: scheduledGames).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) },
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
        var fresh = await summaryGame(response, fallback: game) ?? game
        if fresh.league == .nhl, fresh.isLive { fresh = await enrichHockey([fresh]).first ?? fresh }
        try Task.checkCancellation()
        let competitors = header.sportsObjects("competitions").first?.sportsObjects("competitors") ?? []
        let awayPeriods = competitors.first { $0.sportsText("homeAway") == "away" }?.sportsObjects("linescores") ?? []
        let homePeriods = competitors.first { $0.sportsText("homeAway") == "home" }?.sportsObjects("linescores") ?? []
        func indexed(_ values: [[String: Any]]) -> [Int: [String: Any]] {
            var result: [Int: [String: Any]] = [:]
            for (index, value) in values.enumerated() {
                let period = Int(value.sportsText("period")) ?? index + 1
                if (1...50).contains(period) { result[period] = value }
            }
            return result
        }
        let awayScores = indexed(awayPeriods), homeScores = indexed(homePeriods)
        func score(_ item: [String: Any]?) -> String {
            guard let item else { return "—" }
            return item.sportsText("displayValue").isEmpty ? item.sportsText("value") : item.sportsText("displayValue")
        }
        let scoring = Set(awayScores.keys).union(homeScores.keys).sorted().map { period in
            SportsStatRow(id: String(period), label: "\(game.league == .mlb ? "Inning" : "Period") \(period)",
                away: score(awayScores[period]), home: score(homeScores[period]), period: period)
        }
        let teams = response.sportsObject("boxscore").sportsObjects("teams")
        let away = teams.first { $0.sportsObject("team").sportsText("id") == game.away.id }?.sportsObjects("statistics") ?? []
        let home = teams.first { $0.sportsObject("team").sportsText("id") == game.home.id }?.sportsObjects("statistics") ?? []
        var seen = Set<String>()
        let keys = (away + home).map { $0.sportsText("name") }.filter { !$0.isEmpty && seen.insert($0).inserted }
        let statistics = keys.map { key -> SportsStatRow in
            let a = away.first { $0.sportsText("name") == key }, h = home.first { $0.sportsText("name") == key }
            let value = a ?? h ?? [:]
            let label = ["label", "displayName", "abbreviation", "name"].map { value.sportsText($0) }.first { !$0.isEmpty } ?? key
            return SportsStatRow(id: key, label: label, away: a?.sportsText("displayValue") ?? "—", home: h?.sportsText("displayValue") ?? "—")
        }
        let latest = response.sportsObjects("plays").last?.sportsText("text") ?? response.sportsObject("drives").sportsObject("current").sportsObjects("plays").last?.sportsText("text") ?? ""
        return SportsGameCenter(game: fresh, scoring: scoring, statistics: statistics, latest: latest,
            playByPlay: Self.playByPlay(response), playerStats: Self.playerStatistics(response, game: fresh))
    }

    static func playByPlay(_ response: [String: Any]) -> [SportsPlayPeriod] {
        let drives = response.sportsObject("drives")
        let raw = response.sportsObjects("plays") + drives.sportsObjects("previous").flatMap { $0.sportsObjects("plays") }
            + drives.sportsObject("current").sportsObjects("plays")
        var seen = Set<String>()
        let plays = raw.enumerated().compactMap { index, item -> (Double, Int, SportsGamePlay)? in
            guard let period = Int(item.sportsObject("period").sportsText("number")), (1...50).contains(period) else { return nil }
            let text = item.sportsText("text").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let id = item.sportsText("id").isEmpty ? "\(period):\(item.sportsObject("clock").sportsText("displayValue")):\(text)" : item.sportsText("id")
            guard seen.insert(id).inserted else { return nil }
            let play = SportsGamePlay(id: id, period: period, clock: item.sportsObject("clock").sportsText("displayValue"),
                text: text, awayScore: item.sportsText("awayScore"), homeScore: item.sportsText("homeScore"),
                teamID: item.sportsObject("team").sportsText("id"), scoring: explicitBool(item["scoringPlay"]) == true)
            let sequence = Double(item.sportsText("sequenceNumber")).flatMap { $0.isFinite ? $0 : nil } ?? Double(index)
            return (sequence, index, play)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { $0.2 }
        let grouped = Dictionary(grouping: plays, by: \.period)
        return grouped.keys.sorted().map { SportsPlayPeriod(number: $0, plays: grouped[$0] ?? []) }
    }

    static func playerStatistics(_ response: [String: Any], game: SportsGame) -> [SportsPlayerStatGroup] {
        var groups: [SportsPlayerStatGroup] = []
        for side in response.sportsObject("boxscore").sportsObjects("players") {
            let teamID = side.sportsObject("team").sportsText("id")
            guard [game.away.id, game.home.id].contains(teamID) else { continue }
            for (index, table) in side.sportsObjects("statistics").enumerated() {
                let labels = table["labels"] as? [String] ?? table["names"] as? [String] ?? []
                guard !labels.isEmpty else { continue }
                var seen = Set<String>()
                let players = table.sportsObjects("athletes").compactMap { row -> SportsPlayerStatLine? in
                    let player = row.sportsObject("athlete")
                    let id = player.sportsText("id"), name = player.sportsText("displayName")
                    guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
                    let rawValues = row["stats"] as? [Any] ?? []
                    let values = labels.indices.map { column -> String in
                        guard rawValues.indices.contains(column) else { return "—" }
                        let value = rawValues[column]
                        let text = value as? String ?? (value as? NSNumber)?.stringValue ?? ""
                        return text.isEmpty ? "—" : text
                    }
                    return SportsPlayerStatLine(id: id, name: name, number: player.sportsText("jersey"),
                        position: player.sportsObject("position").sportsText("abbreviation"),
                        photo: player.sportsObject("headshot").sportsText("href"), values: values,
                        didNotPlay: explicitBool(row["didNotPlay"]) == true)
                }
                guard !players.isEmpty else { continue }
                groups.append(SportsPlayerStatGroup(id: "\(teamID):\(index)", teamID: teamID,
                    title: table.sportsText("displayName").isEmpty ? table.sportsText("name").capitalized : table.sportsText("displayName"),
                    labels: labels, descriptions: table["descriptions"] as? [String] ?? [], players: players))
            }
        }
        return groups
    }

    static func validEventID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// Widget links contain ESPN identities, never an arbitrary player URL.
    /// Fetch fresh status and teams before discovering any playable source.
    func game(league: SportsLeague, eventID: String) async throws -> SportsGame {
        guard Self.validEventID(eventID) else { throw SportsServiceError.invalidURL }
        let response = try await object("\(league.endpoint)/summary?event=\(eventID)")
        guard let game = parseGame(response.sportsObject("header"), league: league), game.eventID == eventID else {
            throw SportsServiceError.invalidResponse
        }
        return game
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
        func collegeTeamsMatch(_ item: [String: Any]) -> Bool {
            let home = Set(([game.home.name] + game.home.streamNames).map(normalized).filter { !$0.isEmpty })
            let away = Set(([game.away.name] + game.away.streamNames).map(normalized).filter { !$0.isEmpty })
            func pair(_ first: String, _ second: String) -> Bool {
                (home.contains(first) && away.contains(second)) || (away.contains(first) && home.contains(second))
            }
            let teams = item.sportsObject("teams")
            let first = normalized(teams.sportsObject("home").sportsText("name"))
            let second = normalized(teams.sportsObject("away").sportsText("name"))
            // Structured teams are authoritative: Alabama must not match Alabama State.
            if !first.isEmpty || !second.isEmpty { return pair(first, second) }
            let sides = item.sportsText("title")
                .replacingOccurrences(of: "\\s+(?:vs\\.?|v\\.?|at|versus)\\s+|\\s*@\\s*", with: "\n", options: [.regularExpression, .caseInsensitive])
                .components(separatedBy: "\n").map(normalized)
            return sides.count == 2 && pair(sides[0], sides[1])
        }
        let match = matches.filter { item in
            let date = (item["date"] as? NSNumber)?.doubleValue ?? 0
            let teams = item.sportsObject("teams")
            let names = [normalized(teams.sportsObject("home").sportsText("name")), normalized(teams.sportsObject("away").sportsText("name"))]
            let title = normalized(item.sportsText("title"))
            return item.sportsText("category") == game.league.category && !item.sportsObjects("sources").isEmpty &&
                (date == 1 || abs(date / 1000 - now.timeIntervalSince1970) <= 18 * 3600) &&
                (game.league != .ncaaf || date == 1 || game.date.map { abs(date / 1000 - $0.timeIntervalSince1970) <= 6 * 3600 } == true) &&
                (game.league == .ncaaf ? collegeTeamsMatch(item) : ((names.contains(homeName) && names.contains(awayName)) || (title.contains(homeName) && title.contains(awayName))))
        }.min { abs((($0["date"] as? NSNumber)?.doubleValue ?? 0) / 1000 - now.timeIntervalSince1970) < abs((($1["date"] as? NSNumber)?.doubleValue ?? 0) / 1000 - now.timeIntervalSince1970) }
        return match
    }
}
