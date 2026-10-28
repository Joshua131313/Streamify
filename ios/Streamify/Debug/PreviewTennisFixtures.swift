#if DEBUG
import Foundation

enum PreviewTennisFixtures {
    static func response(_ request: URLRequest) -> (Int, String, Data)? {
        guard let url = request.url else { return nil }
        let enabled = ProcessInfo.processInfo.arguments.contains("--ui-tennis-fixture")
        if url.host == "www.tennislive.net" {
            let route = "/atp/match/jannik-sinner-VS-carlos-alcaraz/vienna-open-2026/"
            let start = Date().addingTimeInterval(-900).timeIntervalSince1970
            if url.path.contains("/match/") {
                let raw: [String: Any] = ["matchDetailPlayerNames": ["Jannik Sinner", "Carlos Alcaraz"], "matchDetailReferenceTimestamp": start]
                let json = String(data: try! JSONSerialization.data(withJSONObject: raw), encoding: .utf8)!
                let html = """
                <script>window.TENNISLIVE_RUNTIME = \(json);</script>
                <section data-set-panel="1"><div class="tl-progress-game"><strong>1-0</strong><span data-progress-server-ball data-player-index="1"></span><div class="text-xs text-black/45">15-0 · 30-0 · 40-0 <span data-progress-outcome>Jannik Sinner wins the game</span></div><span>Serve lost</span></div></section>
                <section data-set-panel="2"><div class="tl-progress-game"><strong>Current game</strong><span data-progress-server-ball data-player-index="0"></span><div class="text-xs text-black/45">15-0 · 15-15</div></div></section>
                """
                return (200, "text/html", Data(html.utf8))
            }
            let match: [String: Any] = ["url": route, "state": "live", "startTimestamp": start, "setLabel": "2nd Set", "server": 0,
                "points": ["15", "15"], "players": [["id": 1, "name": "Jannik Sinner", "setsWon": 1, "sets": [6, 3]], ["id": 2, "name": "Carlos Alcaraz", "setsWon": 0, "sets": [4, 2]]]]
            let group: [String: Any] = ["tour": "atp", "tournamentId": 10, "name": "Vienna Open", "url": "/atp-men/vienna-open-2026/", "rank": 2, "matches": [match]]
            let data = try! JSONSerialization.data(withJSONObject: ["homepageTournaments": enabled ? [group] : []])
            let json = String(data: data, encoding: .utf8)!
            return (200, "text/html", Data("<script>window.TENNISLIVE_RUNTIME = \(json);</script>".utf8))
        }
        if url.host == "site.api.espn.com", url.path.contains("/sports/tennis/") {
            let tour = url.path.contains("/wta/") ? "wta" : "atp"
            let games = enabled ? [tournament(tour)] : []
            let data = (try? JSONSerialization.data(withJSONObject: ["events": games])) ?? Data("{}".utf8)
            return (200, "application/json", data)
        }
        if url.host == "www.tennisexplorer.com" {
            let now = Date(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
            let parts = calendar.dateComponents([.day, .month, .year, .hour, .minute], from: now)
            let date = "\(parts.day!). \(parts.month!). \(parts.year!)"
            let time = String(format: "%02d:%02d", parts.hour!, parts.minute!)
            let rows = enabled ? """
            <tr class="head flags"><td class="t-name"><a href="/seoul-challenger/2026/atp-men/">Seoul Challenger</a></td></tr>
            <tr id="r1"><td class="first time">\(time)</td><td class="t-name"><a href="/player/jasika/">Jasika O.</a></td><td class="result">2</td><td class="score">6</td><td class="score">6</td><td><a href="/match-detail/?id=3361803">info</a></td></tr>
            <tr id="r1b"><td class="t-name"><a href="/player/harris-9f62b/">Harris L.</a></td><td class="result">0</td><td class="score">3</td><td class="score">1</td></tr>
            """ : ""
            return (200, "text/html", Data("<span class='timezone'>GMT+1</span><ul><li class='set'><span class='tab'>\(date)</span></li></ul><table class='result'>\(rows)</table>".utf8))
        }
        return nil
    }

    private static func tournament(_ tour: String) -> [String: Any] {
        let atp = tour == "atp"
        let players = atp ? ["Jannik Sinner", "Carlos Alcaraz"] : ["Iga Swiatek", "Coco Gauff"]
        let competitors: [[String: Any]] = players.enumerated().map { index, name in
            ["id": "\(atp ? 100 : 200)\(index)", "homeAway": index == 0 ? "away" : "home",
             "possession": index == 0, "curatedRank": ["current": index == 0 ? 8 : 0],
             "athlete": ["displayName": name, "shortName": name], "linescores": atp ? [["value": index == 0 ? 6 : 4], ["value": index == 0 ? 3 : 2]] : []]
        }
        let start = Date().addingTimeInterval(atp ? -900 : 1800)
        let competition: [String: Any] = ["id": atp ? "185682" : "185708", "date": ISO8601DateFormatter().string(from: start), "timeValid": true,
            "status": ["type": ["state": atp ? "in" : "pre", "detail": atp ? "2nd Set" : "Scheduled"]],
            "competitors": competitors, "round": ["displayName": "Round of 16"]]
        var doubles = competition
        doubles["id"] = atp ? "185683" : "185709"
        doubles["competitors"] = [["id": "double-away", "homeAway": "away", "athlete": ["displayName": "Doubles Player One / Partner"]],
                                  ["id": "double-home", "homeAway": "home", "athlete": ["displayName": "Doubles Player Two / Partner"]]]
        return ["id": atp ? "10-2026" : "232-2026", "name": atp ? "Vienna Open" : "Guangzhou Open",
                "groupings": [["grouping": ["displayName": atp ? "Men's Singles" : "Women's Singles"], "competitions": [competition]],
                              ["grouping": ["displayName": atp ? "Men's Doubles" : "Women's Doubles"], "competitions": [doubles]]]]
    }
}
#endif
