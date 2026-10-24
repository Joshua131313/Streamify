import SwiftUI

private struct PlayerViewportKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct PlayerDismissGesture: ViewModifier {
    let action: () -> Void
    @State private var viewport: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PlayerViewportKey.self, value: geometry.size)
                }.allowsHitTesting(false)
            }
            .onPreferenceChange(PlayerViewportKey.self) { viewport = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 20, coordinateSpace: .local).onEnded { value in
                let fromHeader = value.startLocation.y <= 70
                let fromRightEdge = viewport.width > 0 && value.startLocation.x >= viewport.width - 32
                guard fromHeader || fromRightEdge, value.translation.width < -90,
                      abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
                action()
            })
    }
}

extension View {
    func playerSwipeToDismiss(action: @escaping () -> Void) -> some View {
        modifier(PlayerDismissGesture(action: action))
    }
}
