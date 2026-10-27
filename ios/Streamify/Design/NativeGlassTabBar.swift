import SwiftUI
import UIKit

/// Let UIKit render its own glass and liquid selection lens. In particular,
/// don't wrap this bar in another glass effect or customize its background
/// appearance: either would replace the system's adaptive material.
@available(iOS 26.0, *)
struct NativeGlassTabBar: UIViewRepresentable {
    let selection: AppTab
    let profile: AppProfile?
    let canSwitchProfiles: Bool
    let select: (AppTab) -> Void
    let openProfiles: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.tintColor = .label
        bar.unselectedItemTintColor = .secondaryLabel
        bar.accessibilityIdentifier = "floating-navigation"
        bar.setItems(AppTab.allCases.enumerated().map { index, tab in
            let item = UITabBarItem(title: tab.title,
                image: UIImage(systemName: tab.symbol),
                selectedImage: UIImage(systemName: tab == .home ? "house.fill" : tab.symbol))
            item.tag = index
            item.accessibilityIdentifier = "tab-\(tab.rawValue)"
            item.accessibilityLabel = tab.title
            return item
        }, animated: false)
        let hold = UILongPressGestureRecognizer(target: context.coordinator,
            action: #selector(Coordinator.heldProfile(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 10
        hold.delegate = context.coordinator
        hold.cancelsTouchesInView = true
        bar.addGestureRecognizer(hold)
        context.coordinator.bar = bar
        updateUIView(bar, context: context)
        return bar
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITabBar, context: Context) -> CGSize? {
        let width = proposal.width ?? 440
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.parent = self
        if let index = AppTab.allCases.firstIndex(of: selection),
           let item = bar.items?[index], bar.selectedItem !== item {
            bar.selectedItem = item
        }
        let avatar = profile?.avatar ?? .crimson
        if context.coordinator.avatar != avatar, let item = bar.items?.last {
            let image = Self.avatarImage(avatar)
            item.image = image
            item.selectedImage = image
            context.coordinator.avatar = avatar
        }
        if let library = bar.items?.last {
            library.accessibilityValue = "Profile: \(profile?.name ?? "My profile"), \(avatar.title) avatar"
            library.accessibilityHint = canSwitchProfiles ? "Touch and hold to switch profiles." : nil
            library.accessibilityCustomActions = canSwitchProfiles ? [
                UIAccessibilityCustomAction(name: "Switch profiles") { [weak coordinator = context.coordinator] _ in
                    guard let coordinator, coordinator.parent.canSwitchProfiles else { return false }
                    coordinator.parent.openProfiles()
                    return true
                }
            ] : nil
        }
    }

    static func dismantleUIView(_ bar: UITabBar, coordinator: Coordinator) {
        bar.delegate = nil
        coordinator.bar = nil
    }

    private static func avatarImage(_ avatar: ProfileAvatar) -> UIImage? {
        guard let artwork = UIImage(named: avatar.artworkName) else { return nil }
        let size = CGSize(width: 25, height: 25)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: 5).addClip()
            artwork.draw(in: rect)
        }.withRenderingMode(.alwaysOriginal)
    }

    @MainActor final class Coordinator: NSObject, UITabBarDelegate, UIGestureRecognizerDelegate {
        var parent: NativeGlassTabBar
        weak var bar: UITabBar?
        var avatar: ProfileAvatar?

        init(parent: NativeGlassTabBar) { self.parent = parent }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard AppTab.allCases.indices.contains(item.tag) else { return }
            parent.select(AppTab.allCases[item.tag])
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.canSwitchProfiles, let bar else { return false }
            let point = gestureRecognizer.location(in: bar)
            // Four equally distributed system items; no private subview or
            // undocumented tab-button frame lookup is involved.
            return bar.bounds.contains(point) && point.x >= bar.bounds.width * 0.75
        }

        @objc func heldProfile(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, parent.canSwitchProfiles else { return }
            // A hold cancels the native contact; it must not also switch tabs.
            if let index = AppTab.allCases.firstIndex(of: parent.selection) {
                bar?.selectedItem = bar?.items?[index]
            }
            parent.openProfiles()
        }
    }
}
