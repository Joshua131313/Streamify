import Foundation
import XCTest
@testable import Streamify

final class DownloadCatalogTests: XCTestCase {
    func testCatalogIdentitySeparatesMoviesShowsAndEpisodes() {
        let movie = MediaItem(id: 123, kind: .movie, title: "Movie")
        let show = MediaItem(id: 123, kind: .tv, title: "Show")
        XCTAssertEqual(DownloadStore.catalogKey(media: movie), "movie:123")
        XCTAssertEqual(DownloadStore.catalogKey(media: movie, season: 9, episode: 17), "movie:123", "Movies have one download regardless of episode selection.")
        XCTAssertEqual(DownloadStore.catalogKey(media: show, season: 2, episode: 3), "tv:123:2:3")
        XCTAssertNotEqual(DownloadStore.catalogKey(media: show, season: 2, episode: 3), DownloadStore.catalogKey(media: show, season: 2, episode: 4))
        XCTAssertNotEqual(DownloadStore.catalogKey(media: movie), DownloadStore.catalogKey(media: show))
    }

    func testOldMetadataDecodesWithoutCatalogFieldsAndKeepsFiles() throws {
        let identifier = UUID()
        let old = """
        {"id":"\(identifier.uuidString)","title":"Imported movie","source":"https://example.com/file.mp4","fileName":"existing.mp4","createdAt":0,"status":"completed","bytesWritten":4096,"expectedBytes":4096}
        """
        let item = try JSONDecoder().decode(DownloadItem.self, from: Data(old.utf8))
        XCTAssertEqual(item.id, identifier)
        XCTAssertEqual(item.fileName, "existing.mp4")
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.bytesWritten, 4096)
        XCTAssertNil(item.catalogKey)
        XCTAssertNil(item.quality)
        let persisted = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(persisted.fileName, "existing.mp4")
    }

    func testSignedExtensionlessURLIsRestrictedToCatalogResolverPath() throws {
        let signed = try XCTUnwrap(URL(string: "https://cdn.example.com/secure/asset?expires=123&signature=a%2Bb"))
        XCTAssertEqual(try DownloadFiles.resolvedURL(signed), signed)
        XCTAssertThrowsError(try DownloadFiles.manualURL(signed.absoluteString))
        XCTAssertEqual(try DownloadFiles.manualURL(" https://example.com/movie.MP4?token=abc \n").pathExtension, "MP4")
        for value in ["http://example.com/movie.mp4", "https://user:password@example.com/movie.mp4", "file:///tmp/movie.mp4"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(try DownloadFiles.resolvedURL(url))
            XCTAssertThrowsError(try DownloadFiles.manualURL(value))
        }
        for suffix in ["m3u8", "mpd", "html", "json"] {
            XCTAssertThrowsError(try DownloadFiles.resolvedURL(XCTUnwrap(URL(string: "https://example.com/asset.\(suffix)"))))
        }
        XCTAssertEqual(DownloadFiles.suffix(for: signed), "mp4")
        XCTAssertEqual(DownloadFiles.suffix(for: URL(string: "https://example.com/asset.token")), "mp4")
        XCTAssertEqual(DownloadFiles.suffix(for: URL(string: "https://example.com/asset.MOV")), "mov")
    }

    func testVideoResponseValidationAcceptsMP4AndRejectsDisguisedPagesAndHLS() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/signed-video"))
        func response(_ mime: String, status: Int = 200) throws -> HTTPURLResponse {
            try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime]))
        }
        let mp4 = Data([0, 0, 0, 24]) + Data("ftypisom".utf8) + Data(repeating: 0, count: 20)
        XCTAssertNoThrow(try DownloadFiles.validateVideo(response: response("video/mp4"), header: mp4))
        XCTAssertNoThrow(try DownloadFiles.validateVideo(response: response("application/octet-stream"), header: mp4))
        let mov = Data([0, 0, 0, 8]) + Data("wide".utf8)
        XCTAssertNoThrow(try DownloadFiles.validateVideo(response: response("video/quicktime"), header: mov))
        XCTAssertThrowsError(try DownloadFiles.validateVideo(response: response("video/mp4", status: 403), header: mp4))
        XCTAssertThrowsError(try DownloadFiles.validateVideo(response: response("text/html"), header: mp4))
        XCTAssertThrowsError(try DownloadFiles.validateVideo(response: response("application/vnd.apple.mpegurl"), header: Data("#EXTM3U\n#EXTINF:10".utf8)))
        for mime in ["video/mp4", "application/octet-stream"] {
            for page in [" \n<!doctype html><html>Denied</html>", "{\"error\":\"expired\"}", "[\"error\"]", "#EXTM3U\n#EXTINF:10"] {
                XCTAssertThrowsError(try DownloadFiles.validateVideo(response: response(mime), header: Data(page.utf8)))
            }
        }
        XCTAssertThrowsError(try DownloadFiles.validateVideo(response: response("application/octet-stream"), header: Data("not a video".utf8)))
        XCTAssertThrowsError(try DownloadFiles.validateVideo(response: response("video/mp4"), header: Data()))
    }

    func testCatalogMetadataRetainsIdentityQualityAndAttemptAcrossPersistence() throws {
        var item = DownloadItem(id: UUID(), title: "Show · S2 E3 · Episode", source: "https://example.com/signed?token=new",
                                createdAt: Date(timeIntervalSince1970: 123), status: .downloading, catalogKey: "tv:123:2:3", quality: 1080)
        item.taskIdentifier = 42
        let restored = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored.catalogKey, "tv:123:2:3")
        XCTAssertEqual(restored.quality, 1080)
        XCTAssertEqual(restored.createdAt, item.createdAt)
        XCTAssertTrue(restored.acceptsCallback(taskIdentifier: 42))
        XCTAssertFalse(restored.acceptsCallback(taskIdentifier: 41))
    }
}
