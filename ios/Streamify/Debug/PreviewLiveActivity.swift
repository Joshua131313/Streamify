#if DEBUG
import ActivityKit
import SwiftUI

/// Exercises the actual bundled widget extension without a score service or APNs.
@MainActor
final class PreviewLiveActivity: ObservableObject {
    static let shared = PreviewLiveActivity()
    static var enabled: Bool { PreviewFixtures.enabled && ProcessInfo.processInfo.arguments.contains("--ui-island-review") }
    @Published var status = "Preparing Live Activity"
    private var leftApp = false
    func update(_ phase: ScenePhase) async {
        guard Self.enabled else { return }
        if phase == .background { leftApp = true; return }
        guard phase == .active else { return }
        if leftApp {
            for activity in Activity<SportsTrackedGameAttributes>.activities where activity.attributes.eventID == "900127" {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            status = "Live Activity ended"
            return
        }
        guard status == "Preparing Live Activity" else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { status = "Live Activities unavailable"; return }
        let attributes = SportsTrackedGameAttributes(league: "nba", eventID: "900127", away: "OKC", home: "DAL", awayID: "25", homeID: "6",
            awayName: "Thunder", homeName: "Mavericks", awayRecord: "3–1", homeRecord: "4–0", venue: "American Airlines Center")
        let state = SportsTrackedGameAttributes.ContentState(awayScore: "93", homeScore: "115", status: "Q4 · 3:12", updatedAt: Date(), final: false)
        do {
            _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(600)), pushType: nil)
            status = "Live Activity ready"
        } catch { status = "Live Activity unavailable: \(error.localizedDescription)" }
    }
}

struct PreviewLiveActivityStatus: View {
    @ObservedObject private var activity = PreviewLiveActivity.shared
    var body: some View {
        Text(activity.status).font(.caption).padding(4).background(.black).foregroundStyle(.white)
            .accessibilityIdentifier("live-activity-review-state")
    }
}
#endif
