import SwiftUI
import ActivityKit

@MainActor
final class SportsGameTracker: ObservableObject {
    static let shared = SportsGameTracker()
    @Published private(set) var tracked = Set<String>()
    @Published private(set) var busy = Set<String>()
    @Published var error: String?
    private var observers: [String: Task<Void, Never>] = [:]

    private init() { restore() }

    private func restore() {
        let activities = Activity<SportsTrackedGameAttributes>.activities.filter { [.active, .stale].contains($0.activityState) }
        tracked = Set(activities.map { $0.attributes.gameKey })
        for activity in activities where observers[activity.id] == nil {
            observers[activity.id] = Task { [weak self] in
                for await state in activity.activityStateUpdates {
                    if state == .dismissed || state == .ended {
                        self?.tracked.remove(activity.attributes.gameKey)
                        self?.observers.removeValue(forKey: activity.id)
                        break
                    }
                }
            }
        }
    }

    func toggle(_ game: SportsGame) async {
        guard !busy.contains(game.id) else { return }
        busy.insert(game.id); defer { busy.remove(game.id) }
        if let activity = Activity<SportsTrackedGameAttributes>.activities.first(where: { $0.attributes.gameKey == game.id }) {
            await activity.end(nil, dismissalPolicy: .immediate)
            tracked.remove(game.id)
            return
        }
        guard SportsService.validEventID(game.eventID), !game.isFinal else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Allow Live Activities for Streamify in iPhone Settings to track a game on your Lock Screen."
            return
        }
        let attributes = SportsTrackedGameAttributes(league: game.league.rawValue, eventID: game.eventID,
            away: game.away.abbreviation, home: game.home.abbreviation, awayID: game.away.id, homeID: game.home.id)
        do {
            _ = try Activity.request(attributes: attributes, content: content(game), pushType: nil)
            restore()
        } catch { self.error = "This game could not be added to the Lock Screen. \(error.localizedDescription)" }
    }

    private func content(_ game: SportsGame) -> ActivityContent<SportsTrackedGameAttributes.ContentState> {
        let now = Date()
        return ActivityContent(state: .init(awayScore: game.away.score, homeScore: game.home.score,
            status: game.status, situation: game.hockeySummary, updatedAt: now, final: game.isFinal),
            staleDate: now.addingTimeInterval(90))
    }

    func refreshWhileActive() async {
        restore()
        while !Task.isCancelled {
            for activity in Activity<SportsTrackedGameAttributes>.activities where [.active, .stale].contains(activity.activityState) {
                guard let league = SportsLeague(rawValue: activity.attributes.league) else { continue }
                do {
                    let service = SportsService()
                    var game = try await service.game(league: league, eventID: activity.attributes.eventID)
                    if game.isLive { game = await service.enrichLiveGames([game], day: Date()).first ?? game }
                    try Task.checkCancellation()
                    if game.isFinal {
                        await activity.end(content(game), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
                        tracked.remove(game.id)
                    } else { await activity.update(content(game)) }
                } catch is CancellationError { return }
                catch { /* The stale date prevents an old snapshot claiming to be current. */ }
            }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
}

struct SportsTrackGameButton: View {
    let game: SportsGame
    @ObservedObject private var tracker = SportsGameTracker.shared
    private var selected: Bool { tracker.tracked.contains(game.id) }
    var body: some View {
        Button { Task { await tracker.toggle(game) } } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "pin.fill" : "pin").font(.system(size: 11))
                Text(selected ? "Tracking" : "Track game")
            }.font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(height: 36)
                .background(AppTheme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.border, lineWidth: 0.7) }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.foreground)
            .disabled(tracker.busy.contains(game.id))
            .accessibilityLabel(selected ? "Stop tracking game" : "Track game on Lock Screen")
            .accessibilityIdentifier("sports-track-\(game.id)")
            .alert("Track game", isPresented: Binding(get: { tracker.error != nil }, set: { if !$0 { tracker.error = nil } })) {
                Button("OK", role: .cancel) { tracker.error = nil }
            } message: { Text(tracker.error ?? "") }
    }
}
