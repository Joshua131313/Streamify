import XCTest
@testable import Streamify

final class CatalogDownloadResolverTests: XCTestCase {
    private let show = MediaItem(id: 124364, kind: .tv, title: "FROM")

    func testNativeVODSourceIsPreferredWithoutContactingTheFileProvider() async throws {
        let resolver = CatalogDownloadResolver(hls: { media, season, episode, quality, _ in
            XCTAssertEqual(media.id, 124364); XCTAssertEqual(season, 1); XCTAssertEqual(episode, 2)
            return Self.source(quality: quality, hls: true)
        }, file: { _, _, _, _, _ in XCTFail("The compatible first source should finish resolution"); throw TestError.failed })
        let result = try await resolver.resolve(media: show, season: 1, episode: 2)
        XCTAssertEqual(result.transport, .hlsVOD)
        XCTAssertEqual(result.quality, 1080)
    }

    func testUnavailableHLSFallsBackToTheSameEpisodeAndResolution() async throws {
        let resolver = CatalogDownloadResolver(hls: { _, _, _, _, _ in throw TestError.failed },
            file: { media, season, episode, quality, _ in
                XCTAssertEqual(media.id, 124364); XCTAssertEqual(season, 2); XCTAssertEqual(episode, 3)
                XCTAssertEqual(quality, 720)
                return Self.source(quality: quality, hls: false)
            })
        let result = try await resolver.resolve(media: show, season: 2, episode: 3, maximumQuality: 720)
        XCTAssertEqual(result.quality, 720)
    }

    func testCancellationNeverStartsAnotherProvider() async {
        let resolver = CatalogDownloadResolver(hls: { _, _, _, _, _ in throw CancellationError() },
            file: { _, _, _, _, _ in XCTFail("Cancellation must stop the whole request"); throw TestError.failed })
        do { _ = try await resolver.resolve(media: show); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testRejectedProviderIsSkippedDuringAutomaticRecovery() async throws {
        let excluded = Set(["https://vixsrc.to/playlist/rejected"])
        let resolver = CatalogDownloadResolver(hls: { _, _, _, _, _ in XCTFail("Rejected provider must be skipped"); throw TestError.failed },
            file: { _, _, _, quality, sources in
                XCTAssertEqual(sources, excluded)
                return Self.source(quality: quality, hls: false)
            })
        let result = try await resolver.resolve(media: show, excludingSources: excluded, excludingProviders: ["VixSrc"])
        XCTAssertEqual(result.transport, .progressiveFile)
    }

    func testWrongResolutionIsRejectedInsteadOfSavedUnderTheChosenLabel() async {
        let resolver = CatalogDownloadResolver(hls: { _, _, _, _, _ in Self.source(quality: 480, hls: true) },
            file: { _, _, _, _, _ in Self.source(quality: 480, hls: false) })
        do { _ = try await resolver.resolve(media: show, maximumQuality: 1080); XCTFail("Wrong quality accepted") }
        catch { XCTAssertEqual(error as? CatalogDownloadResolutionError, .unavailable(quality: 1080)) }
    }

    func testLowerTierUsesOnlyTheFileProviderAndInvalidEpisodeUsesNeither() async throws {
        let resolver = CatalogDownloadResolver(hls: { _, _, _, _, _ in XCTFail("HLS adapter currently advertises only720/1080"); throw TestError.failed },
            file: { _, _, _, quality, _ in Self.source(quality: quality, hls: false) })
        let result = try await resolver.resolve(media: show, maximumQuality: 480)
        XCTAssertEqual(result.quality, 480)
        do { _ = try await resolver.resolve(media: show, episode: 0); XCTFail("Invalid episode accepted") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .invalidEpisode) }
    }

    private enum TestError: Error { case failed }
    private static func source(quality: Int, hls: Bool) -> ResolvedMediaDownload {
        let url = URL(string: hls ? "https://vixsrc.to/playlist/123" : "https://video.example/episode.mp4")!
        var source = ResolvedMediaDownload(url: url, quality: quality, sourceID: hls ? "VixSrc" : "VidLink",
            transport: hls ? .hlsVOD : .progressiveFile, audioLanguage: hls ? "en" : nil)
        if hls { source.hlsSource = HLSDownloadSource(masterURL: url, quality: quality, audioLanguage: "en", protection: .clearOrIdentityAES128, isVOD: true) }
        return source
    }
}
