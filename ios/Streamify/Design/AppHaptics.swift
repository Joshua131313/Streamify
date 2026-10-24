import SwiftUI
import UIKit

/// Feedback belongs to a completed button activation, not a touch anywhere on
/// the screen. Native Button still owns disabled, cancellation and accessibility.
enum AppHaptics {
    enum Kind: Sendable { case selection, primary }

    static func tap(_ kind: Kind = .selection) {
        Task { @MainActor in
            switch kind {
            case .selection: UISelectionFeedbackGenerator().selectionChanged()
            case .primary: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
            }
        }
    }
}

struct HapticPlainButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            AppHaptics.tap()
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(.plain)
    }
}

/// Retain the system's contextual Form/toolbar appearance for default buttons.
struct HapticAutomaticButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            AppHaptics.tap()
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(.automatic)
    }
}

struct HapticBorderedButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role) {
            AppHaptics.tap(prominent ? .primary : .selection)
            configuration.trigger()
        } label: { configuration.label }
        if prominent { button.buttonStyle(.borderedProminent) }
        else { button.buttonStyle(.bordered) }
    }
}
