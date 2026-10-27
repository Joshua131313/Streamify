import AVFoundation
import XCTest
@testable import Streamify

final class HLSDownloadPolicyTests: XCTestCase {
    func testPackageLocationSurvivesContainerChangeWithoutMovingIt() throws {
        let first = URL(fileURLWithPath: "/test/old-container", isDirectory: true)
        let next = URL(fileURLWithPath: "/test/new-container", isDirectory: true)
        let relative = "Library/managed-assets/episode.movpkg"
        let original = first.appendingPathComponent(relative)
        XCTAssertEqual(try HLSDownloadedPackages.relativePath(of: original, home: first), relative)
        XCTAssertEqual(HLSDownloadedPackages.fileURL(for: relative, home: next), next.appendingPathComponent(relative, isDirectory: true))
    }

    func testNativeDirectoryHintIsNotTreatedAsAnUnsafePackageBeforeCreation() throws {
        let home = URL(fileURLWithPath: "/test/nonexistent-container", isDirectory: true)
        let relative = "Library/managed-assets/new.movpkg"
        let directory = home.appendingPathComponent(relative, isDirectory: true)
        let plain = home.appendingPathComponent(relative, isDirectory: false)
        XCTAssertEqual(try HLSDownloadedPackages.relativePath(of: directory, home: home), relative)
        XCTAssertEqual(try HLSDownloadedPackages.relativePath(of: plain, home: home), relative)
        XCTAssertEqual(HLSDownloadedPackages.fileURL(for: relative, home: home)?.path, directory.path)
    }

    func testPackagePathsCannotEscapeAppLibraryOrPointToOrdinaryFiles() {
        let home = URL(fileURLWithPath: "/test/container", isDirectory: true)
        for invalid in ["/Library/episode.movpkg", "Library/../Documents/episode.movpkg", "Library//episode.movpkg",
                        "Library/./episode.movpkg", "Documents/episode.movpkg", "Library/episode.mp4",
                        "Library\\episode.movpkg", "Library", "../outside.movpkg"] {
            XCTAssertNil(HLSDownloadedPackages.fileURL(for: invalid, home: home), invalid)
        }
        XCTAssertThrowsError(try HLSDownloadedPackages.relativePath(of:
            URL(fileURLWithPath: "/test/outside/episode.movpkg"), home: home))
    }

    func testOverlappingTimeRangesDoNotDoubleCountProgress() throws {
        let expected = range(10, 100)
        let loaded = [range(0, 30), range(20, 30), range(45, 25), range(90, 50)]
        // Union inside10...110 is10...70 plus90...110.
        XCTAssertEqual(try XCTUnwrap(HLSDownloadProgress.fraction(loaded: loaded, expected: expected)), 0.8, accuracy: 0.00001)
    }

    func testProgressHandlesUnknownInvalidAndEmptyDurations() {
        XCTAssertNil(HLSDownloadProgress.fraction(loaded: [], expected: .invalid))
        XCTAssertNil(HLSDownloadProgress.fraction(loaded: [], expected: range(0, 0)))
        XCTAssertEqual(HLSDownloadProgress.fraction(loaded: [], expected: range(0, 100)), 0)
        XCTAssertEqual(HLSDownloadProgress.fraction(loaded: [range(0, 300)], expected: range(0, 100)), 1)
    }

    private func range(_ start: Double, _ duration: Double) -> CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: duration, preferredTimescale: 600))
    }
}
