import XCTest
import UIKit
import AVFoundation
@testable import Streamify

final class OfflineSeekPreviewTests: XCTestCase {
    func testThumbAnchoringClampsBothEdgesAndKeepsActualMiddlePosition() {
        XCTAssertEqual(OfflineSeekPreviewMath.center(thumbX: 4, viewportWidth: 390), 104)
        XCTAssertEqual(OfflineSeekPreviewMath.center(thumbX: 386, viewportWidth: 390), 286)
        XCTAssertEqual(OfflineSeekPreviewMath.center(thumbX: 172, viewportWidth: 390), 172)
        XCTAssertEqual(OfflineSeekPreviewMath.center(thumbX: 172, viewportWidth: 180), 90)
    }

    func testPreviewUsesValidWholeSecondsAndNeverRequestsBeyondTheLastFrame() {
        XCTAssertEqual(OfflineSeekPreviewMath.second(position: 12.95, duration: 600), 12)
        XCTAssertEqual(OfflineSeekPreviewMath.second(position: -10, duration: 600), 0)
        XCTAssertEqual(OfflineSeekPreviewMath.second(position: 900, duration: 600), 599)
        XCTAssertNil(OfflineSeekPreviewMath.second(position: .nan, duration: 600))
        XCTAssertNil(OfflineSeekPreviewMath.second(position: 20, duration: .infinity))
        XCTAssertNil(OfflineSeekPreviewMath.second(position: 20, duration: 0))
        XCTAssertEqual(OfflineSeekPreviewMath.timestamp(3665.9), "1:01:05")
    }

    @MainActor
    func testBundledOfflineVideoProducesAnActualBoundedFrame() async throws {
        let source = try XCTUnwrap(Bundle.main.url(forResource: "offline-player", withExtension: "mp4"),
            "The app's same local H264 fixture used by offline playback must be bundled.")
        let model = OfflineSeekPreviewModel()
        defer { model.close() }
        model.show(url: source, seconds: 1, duration: 600)
        let decoded = await settled { !model.loading }
        XCTAssertTrue(decoded)
        let frame = try XCTUnwrap(model.image?.cgImage, "The preview must use a decoded video frame, not a catalog poster.")
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertLessThanOrEqual(frame.width, 320)
        XCTAssertLessThanOrEqual(frame.height, 180)
    }

    @MainActor
    func testRapidScrubbingConflatesPendingFramesAndNeverShowsAnOlderRequest() async throws {
        let gate = FrameGate()
        let model = OfflineSeekPreviewModel { _, time in await gate.load(second: Int(time.seconds)) }
        defer { model.close(); gate.releaseAll() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-conflation.mp4")
        model.show(url: url, seconds: 1, duration: 600)
        let firstStarted = await settled { gate.requested == [1] }
        XCTAssertTrue(firstStarted)
        model.show(url: url, seconds: 2, duration: 600)
        model.show(url: url, seconds: 3, duration: 600)
        gate.release(1)
        let latestStarted = await settled { gate.requested == [1, 3] }
        XCTAssertTrue(latestStarted, "The intermediate pending frame must be skipped.")
        XCTAssertNil(model.image, "The completed first frame must not appear beneath the third frame's timestamp.")
        gate.release(3)
        let latestShown = await settled { model.image != nil && !model.loading }
        XCTAssertTrue(latestShown)
        XCTAssertEqual(model.seconds, 3)
        model.show(url: url, seconds: 3, duration: 600)
        XCTAssertEqual(gate.requested, [1, 3], "Revisiting a decoded second must use the bounded frame cache.")
    }

    @MainActor
    func testHiddenPreviewRejectsLateDecodeEvenWhenAnotherScrubHasStarted() async throws {
        let gate = FrameGate()
        let model = OfflineSeekPreviewModel { _, time in await gate.load(second: Int(time.seconds)) }
        defer { model.close(); gate.releaseAll() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-cancellation.mp4")
        model.show(url: url, seconds: 1, duration: 600)
        let firstStarted = await settled { gate.requested == [1] }
        XCTAssertTrue(firstStarted)
        model.hide()
        XCTAssertFalse(model.visible)
        XCTAssertNil(model.image)
        model.show(url: url, seconds: 8, duration: 600)
        let newStarted = await settled { gate.requested == [1, 8] }
        XCTAssertTrue(newStarted)
        gate.release(1)
        await Task.yield()
        XCTAssertNil(model.image, "A canceled generation cannot publish into a new scrub session.")
        gate.release(8)
        let newShown = await settled { model.image != nil && !model.loading }
        XCTAssertTrue(newShown)
        XCTAssertEqual(model.seconds, 8)
    }

    @MainActor private func settled(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @MainActor private final class FrameGate {
        var requested: [Int] = []
        private var pending: [Int: CheckedContinuation<CGImage, Never>] = [:]
        func load(second: Int) async -> CGImage {
            requested.append(second)
            return await withCheckedContinuation { pending[second] = $0 }
        }
        func release(_ second: Int) {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }.cgImage!
            pending.removeValue(forKey: second)?.resume(returning: image)
        }
        func releaseAll() { for second in Array(pending.keys) { release(second) } }
    }
}
