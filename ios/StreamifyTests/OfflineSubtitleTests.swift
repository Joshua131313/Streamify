import Foundation
import XCTest
@testable import Streamify

final class OfflineSubtitleTests: XCTestCase {
    func testSRTAndVTTParseAsPlainTextWithSortedBoundaryLookup() throws {
        let data = Data("\u{feff}WEBVTT\n\nsecond\n00:03.000 --> 00:04.500 align:start\n<b>Second</b> &amp; safe\n\n1\n00:00:01,250 --> 00:00:02,000\nFirst line\nSecond line\n".utf8)
        let cues = try OfflineSubtitleTrack.parse(data: data)
        XCTAssertEqual(cues.map(\.start), [1.25, 3])
        XCTAssertEqual(cues[1].text, "Second & safe")
        XCTAssertEqual(OfflineSubtitleTrack.text(at: 1.25, cues: cues), "First line\nSecond line")
        XCTAssertEqual(OfflineSubtitleTrack.text(at: 2, cues: cues), "")
        XCTAssertEqual(OfflineSubtitleTrack.text(at: 3.5, cues: cues), "Second & safe")
        XCTAssertEqual(OfflineSubtitleTrack.text(at: .nan, cues: cues), "")
        XCTAssertEqual(OfflineSubtitleTrack.text(at: -1, cues: cues), "")
    }
    func testInvalidEncodingOversizedFilesAndUnsafeTimesAreRejected() {
        XCTAssertThrowsError(try OfflineSubtitleTrack.parse(data: Data([0xff, 0xfe])))
        XCTAssertThrowsError(try OfflineSubtitleTrack.parse(data: Data(repeating: 0x20, count: 2_000_001)))
        for time in ["00:99:01,000", "00:00:NaN", "-1:00:01.000", "99999999999:00:01.000"] {
            XCTAssertThrowsError(try OfflineSubtitleTrack.parse(data: Data("\(time) --> 00:00:10.000\nBad\n".utf8)))
        }
        XCTAssertThrowsError(try OfflineSubtitleTrack.parse(data: Data("WEBVTT\n\nNOTE no cues".utf8)))
    }
    func testCueCountIsBounded() {
        let source = String(repeating: "00:01.000 --> 00:02.000\nFixture\n\n", count: 20_001)
        XCTAssertThrowsError(try OfflineSubtitleTrack.parse(data: Data(source.utf8)))
    }
}
