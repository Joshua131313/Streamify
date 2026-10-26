import Foundation
import Combine

/// Retains rendered league results, including known empty schedules. Switching
/// a filter must not clear a recently fetched result or restart its requests.
@MainActor final class SportsScheduleCache: ObservableObject {
    struct Snapshot {
        let games: [SportsGame]
        let partial: Bool
        let fresh: Bool
    }
    private struct Entry {
        let games: [SportsGame]
        let partial: Bool
        let fetchedAt: Date
    }
    private var entries: [String: Entry] = [:]

    func snapshot(leagues: [SportsLeague], day: Date, backend: String,
                  calendar: Calendar = .current, now: Date = Date()) -> Snapshot? {
        guard !leagues.isEmpty else { return nil }
        let cached = leagues.compactMap { entries[key($0, day: day, backend: backend, calendar: calendar)] }
        guard cached.count == leagues.count else { return nil }
        return Snapshot(games: cached.flatMap(\.games).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) },
                        partial: cached.contains { $0.partial },
                        fresh: cached.allSatisfy { now.timeIntervalSince($0.fetchedAt) >= 0 && now.timeIntervalSince($0.fetchedAt) < 30 })
    }

    func store(_ schedule: SportsSchedule, leagues: [SportsLeague], day: Date, backend: String,
               calendar: Calendar = .current, fetchedAt: Date = Date()) {
        for league in leagues where !schedule.failedLeagues.contains(league) {
            entries[key(league, day: day, backend: backend, calendar: calendar)] = Entry(
                games: schedule.games.filter { $0.league == league }, partial: schedule.partial,
                fetchedAt: fetchedAt)
        }
        if entries.count > 48 {
            for key in entries.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(entries.count - 48).map(\.key) {
                entries[key] = nil
            }
        }
    }

    private func key(_ league: SportsLeague, day: Date, backend: String, calendar: Calendar) -> String {
        "\(backend)|\(calendar.timeZone.identifier)|\(calendar.startOfDay(for: day).timeIntervalSince1970)|\(league.rawValue)"
    }
}
