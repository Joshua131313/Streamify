import XCTest
import WebKit
@testable import Streamify

final class ProviderPopupProtectionTests: XCTestCase {
    func testObservedAdvertisingHostsAreBlockedWithoutBlockingPlayerCDNs() throws {
        for address in ["https://pl29569919.profitableratecpmnetwork.com/ad.js", "https://reviled.thirstacock.com/ad", "https://laborer.cogwayskerb.com/ad",
                        "https://acscdn.com/script/aclib.js", "https://al5sm.com/tag.min.js", "https://clearonclick.com/jump/next.php?r=12277354"] {
            XCTAssertTrue(ProviderPopupProtection.blocks(try XCTUnwrap(URL(string: address))))
        }
        for address in ["https://thedaddy.pk/stream/stream-30.php", "https://dembed.st/premiumtv/daddy.php?id=30",
                        "https://cdn.jwplayer.com/libraries/player.js", "https://cdn.jsdelivr.net/npm/pako@2/dist/pako.min.js",
                        "https://matchora.to/embed/match/2601717", "https://cdnjs.cloudflare.com/ajax/libs/hls.js/1.5.17/hls.min.js",
                        "https://challenges.cloudflare.com/turnstile/v0/api.js", "https://www.gstatic.com/cv/js/sender/v1/cast_sender.js",
                        "https://thirstacock.com.safe.example/player", "https://video.example/watch?host=thirstacock.com"] {
            XCTAssertFalse(ProviderPopupProtection.blocks(try XCTUnwrap(URL(string: address))))
        }
    }

    func testRuleExpressionsOnlyMatchTheObservedHostAndItsSubdomains() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProviderPopupProtection.rules.utf8)) as? [[String: Any]])
        let expressions = try rules.map { rule in
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            return try NSRegularExpression(pattern: XCTUnwrap(trigger["url-filter"] as? String))
        }
        func matches(_ value: String) -> Bool {
            expressions.contains { $0.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil }
        }
        XCTAssertTrue(matches("https://reviled.thirstacock.com/path"))
        XCTAssertTrue(matches("https://profitableratecpmnetwork.com:443/path"))
        XCTAssertTrue(matches("https://acscdn.com/script/aclib.js"))
        XCTAssertTrue(matches("https://al5sm.com/tag.min.js"))
        XCTAssertTrue(matches("https://clearonclick.com/jump/next.php"))
        XCTAssertFalse(matches("https://notthirstacock.com/path"))
        XCTAssertFalse(matches("https://thirstacock.com.safe.example/path"))
        XCTAssertFalse(matches("https://cdn.jwplayer.com/libraries/player.js?ad=thirstacock.com"))
        XCTAssertFalse(matches("https://acscdn.com.player.example/video.m3u8"))
        XCTAssertFalse(matches("https://matchora.to/stream?ad=clearonclick.com"))
    }

    @MainActor func testNativeWebKitCompilerAcceptsTheProductionRuleList() async {
        let compiled: WKContentRuleList? = await withCheckedContinuation { continuation in
            ProviderPopupRuleStore.prepare { continuation.resume(returning: $0) }
        }
        XCTAssertNotNil(compiled, "The production rule set must compile in WebKit before loading a provider.")
    }
}
