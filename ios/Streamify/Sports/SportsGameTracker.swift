import SwiftUI
import ActivityKit
import UIKit

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
        error = nil
        busy.insert(game.id); defer { busy.remove(game.id) }
        if let activity = Activity<SportsTrackedGameAttributes>.activities.first(where: { $0.attributes.gameKey == game.id }) {
            await activity.end(nil, dismissalPolicy: .immediate)
            tracked.remove(game.id)
            return
        }
        guard (game.league == .tennis ? SportsService.validTennisEventID(game.eventID) : SportsService.validEventID(game.eventID)), !game.isFinal else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Allow Live Activities for Streamify in Settings to track a game on your Lock Screen."
            return
        }
        var attributes = SportsTrackedGameAttributes(league: game.league.rawValue, eventID: game.eventID,
            away: game.away.abbreviation, home: game.home.abbreviation, awayID: game.away.id, homeID: game.home.id,
            awayName: game.league == .tennis ? game.away.tennisDisplayName : game.away.name,
            homeName: game.league == .tennis ? game.home.tennisDisplayName : game.home.name,
            awayRecord: game.league == .tennis ? nil : game.away.record, homeRecord: game.league == .tennis ? nil : game.home.record,
            venue: game.venue, start: game.date)
        if game.league == .tennis {
            let portraits = await SportsTennisPortraits.shared.photos(game)
            async let away = Self.trackingPortrait([game.away.portrait.flatMap(sportsHTTPSURL), portraits[game.away.id], game.away.logoURL].compactMap { $0 })
            async let home = Self.trackingPortrait([game.home.portrait.flatMap(sportsHTTPSURL), portraits[game.home.id], game.home.logoURL].compactMap { $0 })
            attributes.awayPortrait = await away; attributes.homePortrait = await home
            // ActivityKit limits attributes and state to 4KB in total.
            if let bytes = try? JSONEncoder().encode(attributes), bytes.count > 3300 {
                attributes.awayPortrait = nil; attributes.homePortrait = nil
            }
        }
        do {
            _ = try Activity.request(attributes: attributes, content: content(game), pushType: nil)
            restore()
        } catch { self.error = "This game could not be added to the Lock Screen. \(error.localizedDescription)" }
    }

    private static func trackingPortrait(_ urls: [URL]) async -> Data? {
        for url in urls {
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 5
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      data.count < 2 * 1024 * 1024, let image = UIImage(data: data) else { continue }
                for side in [56.0, 44.0, 32.0] {
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let size = CGSize(width: side, height: side)
                    let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { context in
                        UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
                        let isFlag = url.path.contains("/countries/")
                        let scale = isFlag ? min(side / image.size.width, side / image.size.height) : max(side / image.size.width, side / image.size.height)
                        let rendered = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: (side - rendered.width) / 2, y: isFlag ? (side - rendered.height) / 2 : 0, width: rendered.width, height: rendered.height))
                    }
                    if let jpeg = thumbnail.jpegData(compressionQuality: 0.4), jpeg.count <= 900 { return jpeg }
                }
            } catch { continue }
        }
        return nil
    }

    private func content(_ game: SportsGame) -> ActivityContent<SportsTrackedGameAttributes.ContentState> {
        let now = Date()
        return ActivityContent(state: .init(awayScore: game.away.score, homeScore: game.home.score,
            status: game.status, situation: game.hockeySummary, updatedAt: now, final: game.isFinal, pregame: game.state == "pre"),
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
    @State private var error: String?
    private var selected: Bool { tracker.tracked.contains(game.id) }
    var body: some View {
        Button { Task { await tracker.toggle(game); error = tracker.error } } label: {
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
            .alert("Track game", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}
