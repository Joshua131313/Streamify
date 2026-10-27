import Foundation
import XCTest
@testable import HLSResearchHost

/// Explicit manual research scope only. Runs the exact resolver which the
/// app calls, with fresh normal provider metadata and Apple's native check.
final class VixSrcProductionResolverDiagnosticsTests: XCTestCase {
    func testProductionResolverOffersExactFromEpisode1080VOD() async {
        var report: [String: Any] = ["observedAt": ISO8601DateFormatter().string(from: Date()),
            "tmdbID": 124364, "season": 1, "episode": 1, "requestedQuality": 1080,
            "completeEpisodeDownloadProven": false, "nativeOfflinePersistenceProven": false]
        do {
            let source = try await VixSrcDownloadResolver().resolve(media:
                MediaItem(id: 124364, kind: .tv, title: "FROM", releaseDate: "2022-02-20"),
                season: 1, episode: 1, quality: 1080)
            XCTAssertEqual(source.transport, .hlsVOD)
            XCTAssertEqual(source.quality, 1080)
            XCTAssertEqual(source.sourceID, "VixSrc")
            XCTAssertEqual(source.audioLanguage, "en")
            XCTAssertEqual(source.actualWidth, 1920)
            XCTAssertEqual(source.actualHeight, 1080)
            XCTAssertEqual(source.hlsSource?.masterURL, source.url)
            XCTAssertEqual(source.hlsSource?.isVOD, true)
            XCTAssertFalse(source.needsRefresh)
            report["sourceID"] = source.sourceID
            report["quality"] = source.quality
            report["nativeWidth"] = source.actualWidth
            report["nativeHeight"] = source.actualHeight
            report["audioLanguage"] = source.audioLanguage
            report["verifiedVOD"] = source.hlsSource?.isVOD
            report["sourceHost"] = source.url.host
            report["sourcePath"] = source.url.path
            report["outcome"] = "Production resolver verified the exact native1080p English VOD source"
        } catch {
            let value = error as NSError
            report["errorDomain"] = value.domain
            report["errorCode"] = value.code
            report["error"] = value.localizedDescription.replacingOccurrences(of: #"https?://\S+"#,
                with: "[source URL]", options: .regularExpression)
            XCTFail("Production VOD resolver failed: \(report["error"] ?? "unknown")")
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Production VOD resolver"; attachment.lifetime = .keepAlways
            add(attachment)
            print("PRODUCTION_HLS_RESOLVER_DIAGNOSTIC \(json)")
        }
    }
}
