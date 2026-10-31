import XCTest
@testable import Streamify

final class ChatAppearanceTests: XCTestCase {
    func testUsernameColorsMatchAndroidAndCanonicalizeCaseWhitespaceAndAccents() {
        XCTAssertEqual(SportsChatContract.nameColorHex("Maya"), "#7ed5b0")
        XCTAssertEqual(SportsChatContract.nameColorHex("Jordan"), "#f3d87a")
        XCTAssertEqual(SportsChatContract.nameColorHex("Élise"), "#b5dc83")
        XCTAssertEqual(SportsChatContract.nameColorHex("  E\u{0301}LISE\n"), "#b5dc83")
        XCTAssertEqual(SportsChatContract.nameColorHex("Maya", light: true), "#14694e")
    }
}
