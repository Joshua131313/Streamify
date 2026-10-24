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

    func testPreviewConvertsActualWindowThumbAndKeepsAndroidBottomInset() {
        let viewport = CGRect(x: 59, y: 24, width: 844, height: 366)
        let thumb = CGRect(x: 320, y: 320, width: 28, height: 28)
        let position = OfflineSeekPreviewMath.position(thumbInWindow: thumb, viewportInWindow: viewport)
        XCTAssertEqual(position.x, 275, "Use the live thumb's center relative to the viewport, not an accessibility frame or playback fraction.")
        XCTAssertEqual(viewport.height - (position.y + OfflineSeekPreviewMath.size.height / 2), 100)

        let lowerThumb = thumb.offsetBy(dx: 0, dy: 36)
        XCTAssertEqual(OfflineSeekPreviewMath.position(thumbInWindow: lowerThumb, viewportInWindow: viewport), position,
            "The timestamp stays below the thumbnail at a fixed canvas inset when slider layout changes.")
        let shiftedViewport = viewport.offsetBy(dx: 43, dy: 61)
        XCTAssertEqual(OfflineSeekPreviewMath.position(thumbInWindow: thumb.offsetBy(dx: 43, dy: 61),
            viewportInWindow: shiftedViewport), position, "Window and safe-area origins must not offset the preview.")
        let safePosition = OfflineSeekPreviewMath.position(thumbInWindow: lowerThumb, viewportInWindow: viewport, bottomSafeAreaInset: 34)
        XCTAssertEqual(viewport.height + 34 - (safePosition.y + OfflineSeekPreviewMath.size.height / 2), 100,
            "The home-indicator safe area must not add an extra gap above the full-screen canvas bottom.")
    }

    func testHigherNativeThumbRaisesPreviewWithoutLosingWindowOrSafeAreaOffsets() {
        let viewport = CGRect(x: 59, y: 62, width: 750, height: 778)
        let thumb = CGRect(x: 320, y: 740, width: 37, height: 37)
        let position = OfflineSeekPreviewMath.position(thumbInWindow: thumb, viewportInWindow: viewport, bottomSafeAreaInset: 34)
        let previewBottomInWindow = viewport.minY + position.y + OfflineSeekPreviewMath.size.height / 2
        XCTAssertEqual(thumb.minY - previewBottomInWindow, 8,
            "The timestamp row must stay above the actual native thumb rather than drawing over the track.")
        XCTAssertGreaterThan(viewport.maxY + 34 - previewBottomInWindow, 100,
            "A higher native control takes priority over Android's preferred bottom inset when they would collide.")
        XCTAssertEqual(position.x, thumb.midX - viewport.minX)
        XCTAssertEqual(OfflineSeekPreviewMath.position(thumbInWindow: thumb.offsetBy(dx: 40, dy: 25),
            viewportInWindow: viewport.offsetBy(dx: 40, dy: 25), bottomSafeAreaInset: 34), position)
    }

    func testPreviewStaysInsideBothHorizontalEdgesAndSafeTopInACompactViewport() {
        let viewport = CGRect(x: 59, y: 24, width: 390, height: 200)
        let first = OfflineSeekPreviewMath.position(thumbInWindow: CGRect(x: 49, y: 150, width: 28, height: 28),
            viewportInWindow: viewport)
        let last = OfflineSeekPreviewMath.position(thumbInWindow: CGRect(x: 431, y: 150, width: 28, height: 28),
            viewportInWindow: viewport)
        XCTAssertEqual(first.x - OfflineSeekPreviewMath.size.width / 2, 0)
        XCTAssertEqual(last.x + OfflineSeekPreviewMath.size.width / 2, viewport.width)
        XCTAssertEqual(first.y - OfflineSeekPreviewMath.size.height / 2, 0,
            "When the 100pt bottom inset cannot fit, the preview must not cross the viewport's safe top.")
        XCTAssertEqual(OfflineSeekPreviewMath.position(thumbInWindow: .zero, viewportInWindow: .zero), .zero)
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
