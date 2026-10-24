import Foundation

enum SportsHomeOrder {
    static func leagues(withGames populated: Set<SportsLeague>) -> [SportsLeague] {
        SportsLeague.allCases.filter { populated.contains($0) } + SportsLeague.allCases.filter { !populated.contains($0) }
    }
}
