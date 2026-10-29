import SwiftUI
import UIKit

/// Measures the available window, including Split View and Stage Manager,
/// rather than assuming that every iPad has a full-screen 12.9-inch viewport.
enum AdaptiveLayout {
    static func columns(width: CGFloat, minimum: CGFloat, spacing: CGFloat = 16, maximum: Int = 4) -> Int {
        max(1, min(maximum, Int((max(0, width) + spacing) / (minimum + spacing))))
    }
    static func usesDetailColumns(width: CGFloat, accessibility: Bool) -> Bool { width >= 900 && !accessibility }
    static var deviceName: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    static var deviceSymbol: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }
}

extension View {
    /// Keep text and forms readable while their background still fills the window.
    func streamifyReadableWidth(_ maximum: CGFloat = 760) -> some View {
        frame(maxWidth: maximum).frame(maxWidth: .infinity)
    }

    func streamifyPageSheet() -> some View { modifier(AdaptivePageSheet()) }
}

private struct AdaptivePageSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.presentationSizing(.page) }
        else { content }
    }
}
