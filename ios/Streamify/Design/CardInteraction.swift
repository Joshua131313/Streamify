import SwiftUI

/// Native Button retains activation, cancellation, disabled and accessibility
/// behavior. Feedback happens once on activation, never while holding or scrolling.
struct HapticCardButtonStyle: PrimitiveButtonStyle {
    var cornerRadius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            AppHaptics.tap()
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(CardPressedButtonStyle(cornerRadius: cornerRadius))
    }
}

/// Native menu sources stay geometrically stable while UIKit decides whether a
/// press is a tap or a hold and lifts its preview. Other cards can scale on press.
struct CardPressedButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    var preservesContextMenuSource = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let content = configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(pressed ? 0.045 : 0))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        if preservesContextMenuSource {
            // Only paint changes during the hold. Keep the source's transform,
            // compositing effects and shadow unchanged through menu dismissal.
            // The system context menu supplies the card's lift animation.
            content.shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)
        } else {
            content
                .scaleEffect(pressed && !reduceMotion ? 0.975 : 1)
                .brightness(pressed ? -0.025 : 0)
                .shadow(color: .black.opacity(pressed ? 0.06 : 0.12), radius: pressed ? 2 : 5, x: 0, y: pressed ? 1 : 3)
                .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: pressed)
        }
    }
}

extension View {
    /// A paint-only edge and ambient shadow; existing sizing, clipping, touch
    /// bounds and accessibility remain owned by the card itself.
    func streamifyCardDepth(cornerRadius: CGFloat = 12) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .black.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 3)
    }
}
