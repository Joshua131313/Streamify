#if DEBUG
import SwiftUI
import Combine

/// Reports real fixture transport activity; compiled out of the installable build.
@MainActor final class PreviewNetworkActivity: ObservableObject {
    static let shared = PreviewNetworkActivity()
    static let enabled = PreviewFixtures.enabled && ProcessInfo.processInfo.arguments.contains("--ui-cache-review")
    @Published var scheduleRequests = 0
    @Published var loadingTransitions = 0
    @Published var failedImages = 0
    @Published var successfulImages = 0
    @Published var repairedMetadata = 0
    @Published var fallbackImages = 0
    nonisolated static func record(_ url: URL, status: Int) {
        Task { @MainActor in
            guard enabled else { return }
            let report = shared
            if url.host == "site.api.espn.com", url.lastPathComponent == "scoreboard" { report.scheduleRequests += 1 }
            if url.host == "image.tmdb.org" {
                if status == 200 { report.successfulImages += 1 } else { report.failedImages += 1 }
                if status == 200 && url.path.contains("fixture-history-fallback") { report.fallbackImages += 1 }
            }
            if url.host == "api.themoviedb.org", url.path == "/3/tv/43" { report.repairedMetadata += 1 }
        }
    }
}

struct PreviewNetworkReport: View {
    @ObservedObject private var report = PreviewNetworkActivity.shared
    var body: some View {
        Text("requests=\(report.scheduleRequests);loading=\(report.loadingTransitions);failedImages=\(report.failedImages);images=\(report.successfulImages);metadata=\(report.repairedMetadata);fallback=\(report.fallbackImages)")
            .font(.system(size: 1)).allowsHitTesting(false).accessibilityIdentifier("fixture-network-report")
    }
}
#endif
