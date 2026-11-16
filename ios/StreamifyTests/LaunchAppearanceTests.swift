import UIKit
import XCTest

/// Render the compiled launch resource itself; these are layout previews, not
/// screenshots of the operating system's transient cold-launch presentation.
@MainActor final class LaunchAppearanceTests: XCTestCase {
    func testCompiledLaunchScreenOnIPhonePortrait() throws {
        try renderLaunchScreen(size: CGSize(width: 393, height: 852), name: "iPhone portrait")
    }

    func testCompiledLaunchScreenOnIPadPortrait() throws {
        try renderLaunchScreen(size: CGSize(width: 1024, height: 1366), name: "iPad portrait")
    }

    func testCompiledLaunchScreenOnIPhoneLandscape() throws {
        try renderLaunchScreen(size: CGSize(width: 852, height: 393), name: "iPhone landscape")
    }

    func testCompiledLaunchScreenOnIPadLandscape() throws {
        try renderLaunchScreen(size: CGSize(width: 1366, height: 1024), name: "iPad landscape")
    }

    private func renderLaunchScreen(size: CGSize, name: String) throws {
        let bundle = Bundle.main
        let storyboardName = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String)
        XCTAssertEqual(storyboardName, "LaunchScreen")
        _ = try XCTUnwrap(bundle.url(forResource: storyboardName, withExtension: "storyboardc"),
                          "The launch storyboard must be compiled into the application bundle.")
        _ = try XCTUnwrap(UIImage(named: "streamify-logo", in: bundle, compatibleWith: nil),
                          "The bundled launch logo asset must resolve.")
        let controller = try XCTUnwrap(UIStoryboard(name: storyboardName, bundle: bundle).instantiateInitialViewController())
        controller.loadViewIfNeeded()
        let view = try XCTUnwrap(controller.view)
        view.frame = CGRect(origin: .zero, size: size)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Compiled launch storyboard - \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let contents = descendants(in: view)
        let logo = try XCTUnwrap(contents.compactMap { $0 as? UIImageView }.first)
        XCTAssertNotNil(logo.image, "The image referenced by the compiled storyboard must load.")
        let labels = contents.compactMap { $0 as? UILabel }
        let decodedLabels = labels.map { $0.attributedText?.string ?? $0.text ?? "nil" }
        let wordmark = try XCTUnwrap(labels.first { $0.text == "STREAMIFY" },
            "Decoded labels: \(decodedLabels)")
        for content in [logo as UIView, wordmark as UIView] {
            let frame = view.convert(content.bounds, from: content)
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertTrue(view.bounds.contains(frame), "Launch branding must remain inside the \(name) canvas.")
            XCTAssertFalse(content.hasAmbiguousLayout, "Launch branding must have a resolved layout.")
        }

    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
