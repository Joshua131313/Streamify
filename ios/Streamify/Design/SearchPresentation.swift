import SwiftUI
import UIKit

private struct SearchSource: ViewModifier {
    let identifier: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.matchedTransitionSource(id: identifier, in: namespace)
        } else { content }
    }
}

private struct SearchPresentation<Destination: View>: ViewModifier {
    @Binding var presented: Bool
    let sourceID: String
    let namespace: Namespace.ID?
    @ViewBuilder let destination: () -> Destination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $presented) {
            if #available(iOS 18, *), !reduceMotion, let namespace {
                destination().navigationTransition(.zoom(sourceID: sourceID, in: namespace))
                    .presentationBackground(AppTheme.canvas)
            } else { destination().presentationBackground(AppTheme.canvas) }
        }
    }
}

/// UIKit delivers appearance after the actual cover/zoom transition. Focusing
/// here keeps the keyboard from resizing content while the search field expands.
private struct SearchPresentationReadiness: UIViewControllerRepresentable {
    let action: () -> Void
    func makeUIViewController(context: Context) -> SearchPresentationObserver {
        let controller = SearchPresentationObserver()
        controller.action = action
        return controller
    }
    func updateUIViewController(_ controller: SearchPresentationObserver, context: Context) { controller.action = action }
    static func dismantleUIViewController(_ controller: SearchPresentationObserver, coordinator: ()) { controller.action = nil }
}

private final class SearchPresentationObserver: UIViewController {
    var action: (() -> Void)?
    private var delivered = false
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !delivered else { return }
        if let coordinator = transitionCoordinator, coordinator.isAnimated {
            let registered = coordinator.animate(alongsideTransition: nil) { [weak self] context in
                if !context.isCancelled { self?.deliver() }
            }
            if !registered { deliver() }
        } else { deliver() }
    }
    private func deliver() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.delivered, self.viewIfLoaded?.window != nil, let action = self.action else { return }
            self.delivered = true
            action()
        }
    }
}

extension View {
    func streamifySearchSource(_ identifier: String, in namespace: Namespace.ID) -> some View {
        modifier(SearchSource(identifier: identifier, namespace: namespace))
    }

    func streamifySearchPresentation<Destination: View>(isPresented: Binding<Bool>, sourceID: String,
        in namespace: Namespace.ID?, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        modifier(SearchPresentation(presented: isPresented, sourceID: sourceID, namespace: namespace, destination: destination))
    }

    func searchPresentationReady(_ action: @escaping () -> Void) -> some View {
        background { SearchPresentationReadiness(action: action).allowsHitTesting(false).accessibilityHidden(true) }
    }
}
