import Foundation
import CoreFoundation

enum SportsTennisFeed {
    static func parse(_ response: [String: Any], tour: SportsTennisTour) -> [SportsGame] {
        guard tour == .atp || tour == .wta else { return [] }
        var result: [SportsGame] = []
        for tournament in response.sportsObjects("events") {
            let tournamentID = tournament.sportsText("id")
            let title = tournament.sportsText("name")
            guard !tournamentID.isEmpty, !title.isEmpty else { continue }
            for group in tournament.sportsObjects("groupings") {
                let discipline = group.sportsObject("grouping").sportsText("displayName")
                for competition in group.sportsObjects("competitions") {
                    let competitionID = competition.sportsText("id")
                    guard SportsService.validEventID(competitionID),
                          let start = SportsService.parseDate(competition.sportsText("startDate").isEmpty ? competition.sportsText("date") : competition.sportsText("startDate")) else { continue }
                    let competitors = competition.sportsObjects("competitors")
                    guard competitors.count == 2 else { continue }
                    let awayRaw = competitors.first { $0.sportsText("homeAway") == "away" } ?? competitors[0]
                    let homeRaw = competitors.first { $0.sportsText("homeAway") == "home" } ?? competitors[1]
                    guard let away = player(awayRaw, tour: tour), let home = player(homeRaw, tour: tour), away.id != home.id else { continue }
                    let type = competition.sportsObject("status").sportsObject("type")
                    let state = type.sportsText("state")
                    guard ["pre", "in", "post"].contains(state) else { continue }
                    let winners = [(awayRaw, away), (homeRaw, home)].filter { explicitBool($0.0["winner"]) == true }
                    let metadata = SportsTennisMatch(tour: tour, tournament: title, tournamentID: tournamentID,
                        discipline: discipline.isEmpty ? "Singles" : discipline,
                        round: competition.sportsObject("round").sportsText("displayName"),
                        awaySets: sets(awayRaw), homeSets: sets(homeRaw),
                        winnerID: winners.count == 1 ? winners.first?.1.id : nil, competitionID: competitionID,
                        timeConfirmed: explicitBool(competition["timeValid"]) == true)
                    let venue = competition.sportsObject("venue")
                    let status = [type.sportsText("detail"), type.sportsText("description")].first { !$0.isEmpty } ?? ""
                    result.append(SportsGame(eventID: "espn-\(tour.rawValue.lowercased())-\(competitionID)", league: .tennis,
                        date: start, state: state, status: status, home: home, away: away,
                        venue: [venue.sportsText("fullName"), venue.sportsText("court")].filter { !$0.isEmpty }.joined(separator: " · "),
                        broadcasts: "", link: tournament.sportsObjects("links").first?.sportsText("href") ?? "", tennis: metadata))
                }
            }
        }
        return SportsScheduleDayPolicy.canonicalGames(result)
    }

    private static func player(_ raw: [String: Any], tour: SportsTennisTour) -> SportsTeam? {
        let athlete = raw.sportsObject("athlete"), roster = raw.sportsObject("roster")
        let name = [athlete.sportsText("displayName"), roster.sportsText("displayName")].first { !$0.isEmpty } ?? ""
        let id = raw.sportsText("id")
        guard !id.isEmpty, !name.isEmpty else { return nil }
        let rank = raw.sportsObject("curatedRank").sportsText("current")
        let short = athlete.sportsText("shortName")
        let scores = raw.sportsObjects("linescores")
        return SportsTeam(id: "\(tour.rawValue.lowercased())-\(id)", name: name, abbreviation: short.isEmpty ? name : short,
            logo: athlete.sportsObject("flag").sportsText("href"),
            score: scores.isEmpty ? "" : String(scores.filter { explicitBool($0["winner"]) == true }.count),
            record: Int(rank).map { $0 > 0 ? "Seed \($0)" : "" } ?? "", streamNames: [name, short].filter { !$0.isEmpty })
    }

    private static func sets(_ raw: [String: Any]) -> [String] {
        raw.sportsObjects("linescores").prefix(5).map { item in
            guard let value = number(item["value"]) else { return "—" }
            if let tiebreak = number(item["tiebreak"]) { return "\(value) (\(tiebreak))" }
            return String(value)
        }
    }
    private static func number(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
              (0...999).contains(value.intValue) else { return nil }
        return value.intValue
    }
    private static func explicitBool(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
}

extension SportsService {
    static func validTennisEventID(_ value: String) -> Bool {
        value.range(of: "^(?:espn-(atp|wta)-[0-9]{1,32}|challenger-[0-9]{1,18})$", options: .regularExpression) != nil
    }
    func tennisSchedule(day: Date, now reference: Date) async throws -> SportsSchedule {
        let raw = try await tennisEvents(around: day)
        return SportsSchedule(games: SportsScheduleDayPolicy.games(raw.games, for: day, now: reference, calendar: calendar),
            failedLeagues: raw.failedLeagues, partial: raw.partial)
    }

    func tennisEvents(around day: Date) async throws -> SportsSchedule {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd"
        var jobs: [(tour: SportsTennisTour, address: String)] = []
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        for offset in -1...1 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            for tour in [SportsTennisTour.atp, .wta] {
                jobs.append((tour, "https://site.api.espn.com/apis/site/v2/sports/tennis/\(tour.rawValue.lowercased())/scoreboard?dates=\(formatter.string(from: date))&limit=1000"))
            }
            let parts = utc.dateComponents([.year, .month, .day], from: date)
            jobs.append((.challenger, "https://www.tennisexplorer.com/matches/?type=all&year=\(parts.year!)&month=\(parts.month!)&day=\(parts.day!)"))
        }
        let requests = jobs
        let batches = try await withThrowingTaskGroup(of: TennisBatch.self, returning: [TennisBatch].self) { group in
            for worker in 0..<3 {
                group.addTask {
                    var batch = TennisBatch()
                    for index in stride(from: worker, to: requests.count, by: 3) {
                        try Task.checkCancellation()
                        let job = requests[index]
                        do {
                            if job.tour == .challenger {
                                let html = try await tennisHTML(job.address)
                                batch.games += try SportsTennisExplorer.parse(html)
                            }
                            else {
                                let raw = try await object(job.address)
                                guard raw["events"] is [[String: Any]] else { throw SportsServiceError.invalidResponse }
                                batch.games += SportsTennisFeed.parse(raw, tour: job.tour)
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch { try Task.checkCancellation(); batch.failures += 1 }
                    }
                    return batch
                }
            }
            var results: [TennisBatch] = []
            for try await result in group { results.append(result) }
            return results
        }
        let failures = batches.reduce(0) { $0 + $1.failures }
        guard failures < jobs.count else { throw SportsServiceError.noSchedule }
        return SportsSchedule(games: SportsScheduleDayPolicy.canonicalGames(batches.flatMap(\.games)), failedLeagues: [], partial: failures > 0)
    }

    func tennisGame(eventID: String, around day: Date? = nil) async throws -> SportsGame {
        guard Self.validTennisEventID(eventID) else { throw SportsServiceError.invalidURL }
        let schedule = try await tennisEvents(around: day ?? now())
        guard let game = schedule.games.first(where: { $0.eventID == eventID }) else { throw SportsServiceError.noSchedule }
        return game
    }

    func tennisCenter(_ game: SportsGame) async throws -> SportsGameCenter {
        let fresh = try await tennisGame(eventID: game.eventID, around: game.date)
        let away = fresh.tennis?.awaySets ?? [], home = fresh.tennis?.homeSets ?? []
        let scoring = (0..<max(away.count, home.count)).map { index in
            SportsStatRow(id: String(index + 1), label: "Set \(index + 1)", away: away.indices.contains(index) ? away[index] : "—",
                home: home.indices.contains(index) ? home[index] : "—", period: index + 1)
        }
        return SportsGameCenter(game: fresh, scoring: scoring, statistics: [], latest: "")
    }

    private func tennisHTML(_ address: String) async throws -> String {
        guard let url = sportsHTTPSURL(address) else { throw SportsServiceError.invalidURL }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Streamify/1.1", forHTTPHeaderField: "User-Agent")
        let prepared = request
        let data = try await ResponseMemoryCache.shared.data(key: ResponseMemoryCache.key(for: prepared, session: session), lifetime: 30,
            reload: forceReload, operation: {
                let (data, response) = try await session.data(for: prepared)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      http.url?.scheme == "https", http.url?.host == "www.tennisexplorer.com",
                      data.count <= 2 * 1024 * 1024 else { throw SportsServiceError.invalidResponse }
                return data
            })
        guard let html = String(data: data, encoding: .utf8) else { throw SportsServiceError.invalidResponse }
        return html
    }
}

private struct TennisBatch: Sendable { var games: [SportsGame] = []; var failures = 0 }
