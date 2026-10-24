import XCTest
import AVFoundation
@testable import Streamify

final class ProviderPlaybackRoutingTests: XCTestCase {
    func testDirectMediaHasARealWebAlternativeAndCanReturnToNative() throws {
        for path in ["video.MP4?expires=123", "live.m3u8?token=test", "video.mov", "video.m4v"] {
            let url = try XCTUnwrap(URL(string: "https://media.example.test/\(path)"))
            XCTAssertEqual(ProviderPlaybackRoute.resolve(url: url, direct: false), .nativeVideo)
            XCTAssertEqual(ProviderPlaybackRoute.resolve(url: url, direct: true), .webDirect,
                "Changing mode must change renderer even for a direct media address")
            XCTAssertEqual(ProviderPlaybackRoute.resolve(url: url, direct: false, webFallback: true), .webDirect,
                "A native error's web fallback must load the media address directly")
            XCTAssertEqual(ProviderPlaybackRoute.resolve(url: url, direct: false, webFallback: false), .nativeVideo)
        }
    }

    func testProviderPagesAndExtensionlessAddressesKeepExistingEmbedDirectBehavior() throws {
        for address in ["https://provider.example.test/embed/movie/550", "https://provider.example.test/watch?id=video.mp4"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(ProviderPlaybackRoute.resolve(url: url, direct: false), .webEmbed)
            XCTAssertEqual(ProviderPlaybackRoute.resolve(url: url, direct: true), .webDirect)
        }
    }

    func testNestedNetworkFailureIsNotMisreportedAsUnsupportedCodec() {
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let wrapper = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: network])
        XCTAssertEqual(ProviderPlaybackFailure.message(for: wrapper, fallback: "Fallback"),
            "The video source could not be reached. Check your connection or try another source.")
        let unclassified = NSError(domain: "FixtureProvider", code: 42,
            userInfo: [NSLocalizedDescriptionKey: "The source is unavailable."])
        XCTAssertEqual(ProviderPlaybackFailure.message(for: unclassified, fallback: "Fallback"), "The source is unavailable.")
    }

    func testOnlyActualDecoderErrorClaimsDecoderUnavailable() {
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decoderNotFound.rawValue)
        XCTAssertEqual(ProviderPlaybackFailure.message(for: error, fallback: "Fallback"),
            "This source needs a decoder that the iOS player cannot use. Choose another source.")
        let access = NSError(domain: NSURLErrorDomain, code: NSURLErrorUserAuthenticationRequired)
        XCTAssertEqual(ProviderPlaybackFailure.message(for: access, fallback: "Fallback"),
            "This source requires access that the iOS player does not have. Try the web player or another source.")
    }
}
