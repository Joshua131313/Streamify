import Foundation
import AVFoundation
import CoreVideo
import XCTest
@testable import Streamify

final class DownloadSourceReliabilityTests: XCTestCase {
    func testSourceContextSurvivesPersistenceAndOldDownloadsRemainReadable() throws {
        let address = try XCTUnwrap(URL(string: "https://cdn.example.test/episode.mp4?signature=a%2Bb"))
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let resolved = ResolvedMediaDownload(url: address, quality: 1080,
            headers: ["Referer": "https://provider.example.test/", "Authorization": "must-not-persist"],
            expiresAt: expiry, codec: "hevc", requiresProxy: true, sourceID: "returned-source")
        var item = DownloadItem(id: UUID(), title: "Episode", source: nil, createdAt: Date(), status: .downloading)
        item.applySource(resolved)
        let restored = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored.source, address.absoluteString)
        XCTAssertEqual(restored.sourceHeaders, ["Referer": "https://provider.example.test/"])
        XCTAssertEqual(restored.sourceExpiresAt, expiry)
        XCTAssertEqual(restored.sourceCodec, "hevc")
        XCTAssertEqual(restored.sourceRequiresProxy, true)
        XCTAssertEqual(restored.sourceID, "returned-source")
        XCTAssertFalse(restored.sourceNeedsRefresh(now: expiry.addingTimeInterval(-31)))
        XCTAssertTrue(restored.sourceNeedsRefresh(now: expiry.addingTimeInterval(-29)))
        let old = """
        {"id":"\(UUID().uuidString)","title":"Old download","createdAt":0,"status":"completed"}
        """
        let legacy = try JSONDecoder().decode(DownloadItem.self, from: Data(old.utf8))
        XCTAssertNil(legacy.sourceHeaders)
        XCTAssertNil(legacy.sourceExpiresAt)
        XCTAssertFalse(legacy.sourceNeedsRefresh(now: expiry))
    }

    func testActualDownloadRequestUsesSafeHeadersAndRedirectDoesNotLeakContext() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.test/file.mp4"))
        let request = DownloadSourceHeaders.request(url: url, headers: [
            "referer": "https://provider.example.test/episode", "Origin": "https://provider.example.test",
            "User-Agent": "Fixture player", "Authorization": "secret", "Cookie": "session=secret",
            "Range": "bytes=1-2", "Accept-Language": "en\r\nInjected: true"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://provider.example.test/episode")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Fixture player")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Accept-Language"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        var redirect = request
        redirect.url = URL(string: "https://other.example.test/file.mp4")
        redirect.setValue("private", forHTTPHeaderField: "Authorization")
        let crossOrigin = try XCTUnwrap(DownloadSourceHeaders.redirected(redirect, from: url))
        for name in ["Referer", "Origin", "Authorization", "Cookie"] { XCTAssertNil(crossOrigin.value(forHTTPHeaderField: name)) }
        let sameOrigin = try XCTUnwrap(DownloadSourceHeaders.redirected(request, from: url))
        XCTAssertEqual(sameOrigin.value(forHTTPHeaderField: "Referer"), request.value(forHTTPHeaderField: "Referer"))
        for address in ["http://other.example.test/file.mp4", "https://user:password@other.example.test/file.mp4", "https://other.example.test:8443/file.mp4"] {
            redirect.url = URL(string: address)
            XCTAssertNil(DownloadSourceHeaders.redirected(redirect, from: url))
        }
    }

    func testQualityUsesActualDimensionsIncludingCroppedAndPortraitVideo() {
        for dimensions in [(1920, 1080), (1920, 804), (1440, 1080), (1080, 1920)] {
            XCTAssertNoThrow(try OfflineVideoValidation.requireQuality(1080, width: dimensions.0, height: dimensions.1))
        }
        XCTAssertNoThrow(try OfflineVideoValidation.requireQuality(720, width: 1280, height: 534))
        XCTAssertNoThrow(try OfflineVideoValidation.requireQuality(480, width: 854, height: 480))
        for dimensions in [(854, 480), (1280, 720), (3840, 2160), (0, 1080)] {
            XCTAssertThrowsError(try OfflineVideoValidation.requireQuality(1080, width: dimensions.0, height: dimensions.1)) {
                XCTAssertEqual($0 as? OfflineVideoError, .qualityMismatch)
            }
        }
        XCTAssertThrowsError(try OfflineVideoValidation.requireQuality(720, width: 1920, height: 1080))
    }

    func testBundledH264MetadataAndNativeResultAgreeOnActualDimensions() async throws {
        let file = try XCTUnwrap(Bundle(for: DownloadStore.self).url(forResource: "offline-player", withExtension: "mp4"))
        let data = try Data(contentsOf: file)
        let parsed = try DownloadSourceProbe.metadata(in: data)
        let native = try await OfflineVideoValidation.validate(file)
        XCTAssertEqual(parsed.width, 320)
        XCTAssertEqual(parsed.height, 180)
        XCTAssertTrue(parsed.codecs.contains("avc1"))
        XCTAssertEqual(native.width, parsed.width)
        XCTAssertEqual(native.height, parsed.height)
        XCTAssertTrue(native.codecs.contains("avc1"))
        XCTAssertThrowsError(try OfflineVideoValidation.requireQuality(1080, width: native.width, height: native.height))
    }

    func testRealNativeHEVCWriterOutputIsInspectedWithoutRetagging() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hevc-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 180]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw XCTSkip("This simulator has no native HEVC encoder; no HEVC support result is fabricated.")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        XCTAssertTrue(writer.canAdd(input)); writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? OfflineVideoError.unplayable }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) { base.initializeMemory(as: UInt8.self, repeating: 128, count: CVPixelBufferGetDataSize(pixel)) }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for frame in 0..<3 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData, writer.status == .writing, Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
            guard input.isReadyForMoreMediaData else { throw writer.error ?? OfflineVideoError.unplayable }
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 5)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? OfflineVideoError.unplayable }
        let original = try Data(contentsOf: url)
        let metadata = try DownloadSourceProbe.metadata(in: original)
        XCTAssertEqual(metadata.width, 320)
        XCTAssertEqual(metadata.height, 180)
        XCTAssertTrue(metadata.codecs.contains("hvc1") || metadata.codecs.contains("hev1"))
        let native = try await OfflineVideoValidation.validate(url)
        XCTAssertGreaterThan(native.duration, 0)
        XCTAssertEqual(native.width, 320)
        XCTAssertTrue(native.codecs.contains("hvc1") || native.codecs.contains("hev1"))
        XCTAssertEqual(try Data(contentsOf: url), original, "Inspection must not change sample tags or media bytes")
    }

    func testExactQualityCandidatesPreserveHeadersTTLCodecAndActualResolution() async throws {
        let fixture = DownloadReliabilityFixture(qualities: ["1080": file("good.mp4", codec: "hevc")],
            files: ["good.mp4": .video(Self.movie(width: 1920, height: 1080, codec: "hev1"))])
        let before = Date()
        let result = try await fixture.resolve()
        XCTAssertEqual(result.quality, 1080)
        XCTAssertEqual(result.codec, "hevc")
        XCTAssertTrue(result.requiresProxy, "A hint must be preserved, without rejecting an actually reachable direct file")
        XCTAssertEqual(result.headers, ["Referer": "https://provider.example.test/"])
        XCTAssertEqual(result.sourceID, "returned-provider")
        XCTAssertEqual(result.actualWidth, 1920)
        XCTAssertEqual(result.actualHeight, 1080)
        XCTAssertEqual(result.actualCodecs, ["hev1"])
        XCTAssertGreaterThan(try XCTUnwrap(result.expiresAt).timeIntervalSince(before), 3500)
        let probe = try XCTUnwrap(fixture.requests.first { $0.url?.lastPathComponent == "good.mp4" })
        XCTAssertEqual(probe.value(forHTTPHeaderField: "Referer"), "https://provider.example.test/")
        XCTAssertEqual(probe.value(forHTTPHeaderField: "Range"), "bytes=0-65535")
        XCTAssertEqual(fixture.requests.count, 3)
    }

    func testMislabeledFileFallsBackOnlyToAnotherReturnedExactQualityCandidate() async throws {
        let fixture = DownloadReliabilityFixture(qualities: ["1080": [file("low.mp4"), file("right.mp4")],
            "720": file("must-not-fetch.mp4")], files: [
                "low.mp4": .video(Self.movie(width: 854, height: 480)),
                "right.mp4": .video(Self.movie(width: 1920, height: 804))])
        let result = try await fixture.resolve()
        XCTAssertEqual(result.url.lastPathComponent, "right.mp4")
        XCTAssertEqual(result.quality, 1080)
        XCTAssertFalse(fixture.requests.contains { $0.url?.lastPathComponent == "must-not-fetch.mp4" })
    }

    func testNo720EntryHasQualityUnavailableAndNeverProbes1080Or480() async throws {
        let fixture = DownloadReliabilityFixture(qualities: ["1080": file("1080.mp4"), "480": file("480.mp4")], files: [:])
        do { _ = try await fixture.resolve(quality: 720); XCTFail("A missing exact tier must not download another quality") }
        catch { XCTAssertEqual(error as? MediaDownloadResolutionError, .qualityUnavailable) }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testDisguisedPageAndOneFailedChannelDoNotHideAValidExactQualityFile() async throws {
        let fixture = DownloadReliabilityFixture(qualities: ["1080": [file("expired.mp4"), file("page.mp4"), file("good.mp4")]], files: [
            "expired.mp4": .status(403), "page.mp4": .body(Data("<html>Expired download</html>".utf8), "video/mp4"),
            "good.mp4": .video(Self.movie(width: 1920, height: 1080))])
        let result = try await fixture.resolve()
        XCTAssertEqual(result.url.lastPathComponent, "good.mp4")
    }

    func testRateLimitStopsWithoutHammeringAnotherCandidateOrClaimingUnsupported() async {
        let fixture = DownloadReliabilityFixture(qualities: ["1080": [file("busy.mp4"), file("second.mp4")]], files: ["busy.mp4": .status(429)])
        do { _ = try await fixture.resolve(); XCTFail("A429 must stop source probing") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("429"))
            XCTAssertFalse(error.localizedDescription.contains("cannot be played"))
        }
        XCTAssertEqual(fixture.requests.count, 3)
    }

    func testAlreadyRejectedPhysicalURLIsNotInspectedAgain() async throws {
        let fixture = DownloadReliabilityFixture(qualities: ["1080": [file("bad.mp4"), file("good.mp4")]],
            files: ["good.mp4": .video(Self.movie(width: 1920, height: 1080))])
        let result = try await fixture.resolve(excluding: ["https://cdn.example.test/bad.mp4"])
        XCTAssertEqual(result.url.lastPathComponent, "good.mp4")
        XCTAssertFalse(fixture.requests.contains { $0.url?.lastPathComponent == "bad.mp4" })
    }

    func testProbeCanJumpPastMediaDataToTheActualMovieMetadata() async throws {
        let compact = Self.movie(width: 1920, height: 1080)
        var mediaSize = UInt32(100_008).bigEndian
        let media = withUnsafeBytes(of: &mediaSize) { Data($0) } + Data("mdat".utf8) + Data(repeating: 0, count: 100_000)
        let withMovieAtEnd = compact.prefix(16) + media + compact.dropFirst(16)
        let fixture = DownloadReliabilityFixture(qualities: ["1080": file("tail.mp4")], files: ["tail.mp4": .video(Data(withMovieAtEnd))])
        let result = try await fixture.resolve()
        XCTAssertEqual(result.quality, 1080)
        let ranges = fixture.requests.filter { $0.url?.lastPathComponent == "tail.mp4" }.compactMap { $0.value(forHTTPHeaderField: "Range") }
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[1], "bytes=100024-100039")
    }

    func testCancellationStopsTheOwnedMetadataRangeTask() async {
        let started = expectation(description: "range started")
        let fixture = DownloadReliabilityFixture(qualities: ["1080": file("pending.mp4")], files: ["pending.mp4": .pending(started)])
        let task = Task { try await fixture.resolve() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled metadata probe must not resolve") }
        catch { XCTAssertTrue(error is CancellationError) }
        for _ in 0..<50 where fixture.scenario.cancelledPendingTasks == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertGreaterThan(fixture.scenario.cancelledPendingTasks, 0)
    }

    func testMalformedMovieMetadataAndProtectedTrackFailClosed() {
        XCTAssertThrowsError(try DownloadSourceProbe.metadata(in: Data([0, 0, 0, 4, 109, 111, 111, 118])))
        XCTAssertThrowsError(try DownloadSourceProbe.metadata(in: Self.movie(width: 1920, height: 1080, codec: "encv"))) {
            XCTAssertEqual($0 as? OfflineVideoError, .protectedContent)
        }
        XCTAssertThrowsError(try DownloadSourceProbe.metadata(in: Self.movie(width: 0, height: 0)))
    }

    private func file(_ name: String, codec: String = "h264") -> [String: Any] {
        ["url": "https://cdn.example.test/\(name)", "headers": ["Referer": "https://provider.example.test/"],
         "codecName": codec, "requiresProxy": true]
    }
    private static func movie(width: Int, height: Int, codec: String = "avc1") -> Data {
        func box(_ kind: String, _ body: Data) -> Data {
            var size = UInt32(body.count + 8).bigEndian
            return withUnsafeBytes(of: &size) { Data($0) } + Data(kind.utf8) + body
        }
        var visual = Data(repeating: 0, count: 78)
        visual[24] = UInt8((width >> 8) & 255); visual[25] = UInt8(width & 255)
        visual[26] = UInt8((height >> 8) & 255); visual[27] = UInt8(height & 255)
        let stsd = box("stsd", Data([0, 0, 0, 0, 0, 0, 0, 1]) + box(codec, visual))
        return box("ftyp", Data("isom0000".utf8)) + box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd)))))
    }
}

private final class DownloadReliabilityFixture {
    enum Reply { case video(Data), body(Data, String), status(Int), pending(XCTestExpectation) }
    let session: URLSession
    let scenario: DownloadReliabilityScenario
    var requests: [URLRequest] { scenario.requests }
    private let id = UUID().uuidString
    init(qualities: [String: Any], files: [String: Reply]) {
        scenario = DownloadReliabilityScenario(qualities: qualities, files: files)
        DownloadReliabilityProtocol.register(scenario, id: id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadReliabilityProtocol.self]
        config.httpAdditionalHeaders = ["X-Download-Reliability-Fixture": id]
        session = URLSession(configuration: config)
    }
    deinit { session.invalidateAndCancel(); DownloadReliabilityProtocol.unregister(id) }
    func resolve(quality: Int = 1080, excluding: Set<String> = []) async throws -> ResolvedMediaDownload {
        try await MediaDownloadResolver(session: session).resolve(media: MediaItem(id: 124364, kind: .tv, title: "Fixture episode"),
            maximumQuality: quality, excludingSources: excluding)
    }
}
private final class DownloadReliabilityScenario {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let qualities: [String: Any]
    private let files: [String: DownloadReliabilityFixture.Reply]
    private var pendingCancellations = 0
    var cancelledPendingTasks: Int { lock.lock(); defer { lock.unlock() }; return pendingCancellations }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(qualities: [String: Any], files: [String: DownloadReliabilityFixture.Reply]) { self.qualities = qualities; self.files = files }
    func reply(_ request: URLRequest) -> (Int, [String: String], Data)? {
        lock.lock(); defer { lock.unlock() }; recorded.append(request)
        if request.url?.host == "enc-dec.app" { return json(["result": "fixturetoken"]) }
        if request.url?.host == "vidlink.pro" { return json(["sourceId": "returned-provider", "stream": ["type": "file", "TTL": 3600, "qualities": qualities]]) }
        guard request.url?.host == "cdn.example.test", let name = request.url?.lastPathComponent, let reply = files[name] else { return nil }
        switch reply {
        case .pending: return nil
        case .status(let status): return (status, ["Content-Type": "text/plain"], Data())
        case .body(let data, let mime): return (200, ["Content-Type": mime, "Content-Length": String(data.count)], data)
        case .video(let data):
            let range = request.value(forHTTPHeaderField: "Range") ?? ""
            let parts = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-")
            guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start < data.count else { return nil }
            let last = min(end, data.count - 1)
            let body = data.subdata(in: start..<(last + 1))
            return (206, ["Content-Type": "video/mp4", "Content-Length": String(body.count),
                "Content-Range": "bytes \(start)-\(last)/\(data.count)", "ETag": "fixture-v1"], body)
        }
    }
    func pending(_ request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let name = request.url?.lastPathComponent, case .pending(let started)? = files[name] { started.fulfill(); return true }
        return false
    }
    func cancelledPending() { lock.lock(); defer { lock.unlock() }; pendingCancellations += 1 }
    private func json(_ object: [String: Any]) -> (Int, [String: String], Data) {
        (200, ["Content-Type": "application/json"], try! JSONSerialization.data(withJSONObject: object))
    }
}
private final class DownloadReliabilityProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var registry: [String: DownloadReliabilityScenario] = [:]
    private var pendingScenario: DownloadReliabilityScenario?
    static func register(_ scenario: DownloadReliabilityScenario, id: String) { lock.lock(); defer { lock.unlock() }; registry[id] = scenario }
    static func unregister(_ id: String) { lock.lock(); defer { lock.unlock() }; registry[id] = nil }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-Download-Reliability-Fixture").flatMap { Self.registry[$0] }
        Self.lock.unlock()
        let reply = scenario?.reply(request)
        if scenario?.pending(request) == true { pendingScenario = scenario; return }
        guard let url = request.url, let (status, headers, data) = reply,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { pendingScenario?.cancelledPending(); pendingScenario = nil }
}
