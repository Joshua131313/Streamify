#if DEBUG
import Foundation

enum PreviewTennisFixtures {
    static func response(_ request: URLRequest) -> (Int, String, Data)? {
        guard let url = request.url else { return nil }
        let enabled = ProcessInfo.processInfo.arguments.contains("--ui-tennis-fixture")
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
