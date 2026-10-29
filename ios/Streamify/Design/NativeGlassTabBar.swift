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
        let bar = NativeGlassTabBarView()
        bar.delegate = context.coordinator
        bar.tintColor = .label
        bar.unselectedItemTintColor = .secondaryLabel
        if UIDevice.current.userInterfaceIdiom == .pad {
            // This standalone floating bar keeps the same stacked icon/caption
            // layout as iPhone. Regular-width UIKit uses an inline presentation
            // that collapses unselected captions even with itemPositioning.fill.
            // Override only the control, leaving the app's iPad layouts regular.
            bar.traitOverrides.horizontalSizeClass = .compact
            bar.itemPositioning = .fill
        }
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
        // Observe the contact without replacing UIKit's liquid-lens tracking.
        // Navigation commits once on release; moving outside cancels it.
        let contact = UILongPressGestureRecognizer(target: context.coordinator,
            action: #selector(Coordinator.contactChanged(_:)))
        contact.minimumPressDuration = 0
        contact.allowableMovement = .greatestFiniteMagnitude
        contact.delegate = context.coordinator
        contact.cancelsTouchesInView = false
        bar.addGestureRecognizer(contact)
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
        if context.coordinator.parent.selection != selection {
            context.coordinator.cancelContact()
        }
        context.coordinator.parent = self
        if !context.coordinator.isTracking,
           let index = AppTab.allCases.firstIndex(of: selection), let item = bar.items?[index] {
            if let native = bar as? NativeGlassTabBarView, !native.didApplyInitialSelection {
                native.selectionAfterLayout = item
                native.setNeedsLayout()
            } else if bar.selectedItem !== item {
                bar.selectedItem = item
            }
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
        coordinator.cancelContact()
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
        private var contactID: UUID?
        private var pendingSelection: AppTab?
        private var holdTask: Task<Void, Never>?
        private var origin = CGPoint.zero
        private var consumedHold = false
        var isTracking: Bool { contactID != nil }

        init(parent: NativeGlassTabBar) { self.parent = parent }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard AppTab.allCases.indices.contains(item.tag) else { return }
            let tab = AppTab.allCases[item.tag]
            if isTracking { pendingSelection = tab }
            else { parent.select(tab) } // VoiceOver and keyboard activation.
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func contactChanged(_ gesture: UILongPressGestureRecognizer) {
            guard let bar else { return }
            let point = gesture.location(in: bar)
            switch gesture.state {
            case .began:
                cancelContact()
                let id = UUID()
                contactID = id; origin = point
                if parent.canSwitchProfiles && isProfileSlot(point, in: bar) {
                    holdTask = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                        guard let self, self.contactID == id, self.parent.canSwitchProfiles else { return }
                        self.consumedHold = true
                        self.restoreCommittedSelection()
                        self.parent.openProfiles()
                    }
                }
            case .changed:
                if hypot(point.x - origin.x, point.y - origin.y) > 8 {
                    holdTask?.cancel(); holdTask = nil
                }
            case .ended:
                holdTask?.cancel(); holdTask = nil
                let id = contactID
                let inside = bar.bounds.insetBy(dx: -20, dy: -24).contains(point)
                // Native item actions may be delivered later in this same
                // touch event. Let UIKit finish before committing the page.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.contactID == id, id != nil else { return }
                    let target = self.pendingSelection ?? self.bar?.selectedItem.flatMap { item in
                        AppTab.allCases.indices.contains(item.tag) ? AppTab.allCases[item.tag] : nil
                    }
                    let commit = inside && !self.consumedHold
                    self.contactID = nil; self.pendingSelection = nil; self.consumedHold = false
                    if commit, let target { self.parent.select(target) }
                    else { self.restoreCommittedSelection() }
                }
            case .cancelled, .failed:
                cancelContact()
            default: break
            }
        }

        func cancelContact() {
            holdTask?.cancel(); holdTask = nil
            contactID = nil; pendingSelection = nil; consumedHold = false
            restoreCommittedSelection()
        }

        private func restoreCommittedSelection() {
            if let index = AppTab.allCases.firstIndex(of: parent.selection) {
                bar?.selectedItem = bar?.items?[index]
            }
        }

        private func isProfileSlot(_ point: CGPoint, in bar: UITabBar) -> Bool {
            let inTrailingQuarter = bar.effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? point.x <= bar.bounds.width * 0.25 : point.x >= bar.bounds.width * 0.75
            return inTrailingQuarter && bar.bounds.insetBy(dx: 0, dy: -24).contains(point)
        }
    }
}

/// Selecting while the representable still has zero-width bounds caches a
/// truncated initial caption in UIKit. Select once at the first real layout;
/// later selection and all lens animation remain entirely system-managed.
@available(iOS 26.0, *)
private final class NativeGlassTabBarView: UITabBar {
    var selectionAfterLayout: UITabBarItem?
    private(set) var didApplyInitialSelection = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didApplyInitialSelection, window != nil, bounds.width > 0, bounds.height > 0,
              let item = selectionAfterLayout else { return }
        didApplyInitialSelection = true
        selectionAfterLayout = nil
        UIView.performWithoutAnimation {
            selectedItem = nil
            selectedItem = item
            setNeedsLayout()
        }
    }
}
