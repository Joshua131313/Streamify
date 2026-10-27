import SwiftUI

/// A floating control, rather than a page gesture: dragging previews a tab and
/// commits it on release. The underlying root page stays mounted while scrubbing.
struct LiquidGlassBottomBar: View {
    @Binding var selection: AppTab
    let onSelectProfile: (UUID) -> Void
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9.5
    @State private var touch: BarTouch?
    @State private var dragCenter: CGFloat?
    @State private var preview: AppTab?
    @State private var holdTask: Task<Void, Never>?
    @State private var profilesOpen = false
    @State private var pendingProfile: UUID?
    @State private var pendingOwner: String?

    private static let coordinateSpace = "streamify-liquid-bottom-bar"
    private let height: CGFloat = 56
    private let inset: CGFloat = 3
    private var focusedTab: AppTab { preview ?? selection }
    private var settlingAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }
    private var restingOpacity: Double { contrast == .increased ? 0.78 : 0.58 }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - inset * 2)
            let cellWidth = width / CGFloat(AppTab.allCases.count)
            let center = dragCenter ?? tabCenter(selection, width: width)
            ZStack(alignment: .leading) {
                selectionLens
                    .frame(width: max(1, cellWidth - 2), height: height - inset * 2)
                    .scaleEffect(x: dragCenter == nil || reduceMotion ? 1 : 1.035,
                                 y: dragCenter == nil || reduceMotion ? 1 : 1.04)
                    .offset(x: inset + center - cellWidth / 2 + 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        tabControl(tab, width: width)
                            .frame(width: cellWidth, height: height - inset * 2)
                    }
                }
                .padding(inset)
            }
            .frame(height: height)
            .modifier(LiquidGlassBarSurface(reduceTransparency: reduceTransparency,
                                          reduceMotion: reduceMotion, dark: colorScheme == .dark))
            .coordinateSpace(name: Self.coordinateSpace)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("floating-navigation")
        }
        .frame(height: height).frame(maxWidth: 400)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.1), radius: 14, y: 5)
        .padding(.horizontal, 50).padding(.top, 4)
        .onChange(of: selection) { _, _ in if touch != nil { cancelTouch(animated: false) } }
        .onChange(of: profilesOpen) { _, open in if open { cancelTouch(animated: false) } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelTouch(animated: false)
                pendingProfile = nil; pendingOwner = nil; profilesOpen = false
            }
        }
        .onDisappear {
            cancelTouch(animated: false)
            pendingProfile = nil; pendingOwner = nil; profilesOpen = false
        }
    }

    private var selectionLens: some View {
        Capsule()
            .fill(AppTheme.foreground.opacity(colorScheme == .dark ? 0.12 : 0.075))
            .overlay {
                Capsule().fill(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.07 : 0.24),
                                                       Color.clear, Color.white.opacity(0.025)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.22 : 0.5),
                                                               AppTheme.foreground.opacity(0.025)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
            }
    }

    @ViewBuilder
    private func tabControl(_ tab: AppTab, width: CGFloat) -> some View {
        if tab == .library {
            tabButton(tab, width: width)
                .accessibilityHint("Touch and hold to switch profiles.")
                .accessibilityAction(named: Text("Switch profiles"), openProfiles)
                .popover(isPresented: $profilesOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    LiquidGlassQuickProfilePicker { profile in
                        guard profilesOpen, pendingProfile == nil else { return }
                        AppHaptics.tap(.primary)
                        if profile.id != profiles.activeProfile?.id {
                            pendingProfile = profile.id; pendingOwner = profiles.ownerUID
                        }
                        profilesOpen = false
                    }
                    .environmentObject(profiles)
                    .presentationCompactAdaptation(.popover)
                    .onDisappear(perform: finishProfileSelection)
                }
        } else {
            tabButton(tab, width: width)
        }
    }

    private func tabButton(_ tab: AppTab, width: CGFloat) -> some View {
        let primary = focusedTab == tab
        return Button { select(tab, feedback: true) } label: {
            VStack(spacing: 1) {
                Group {
                    if tab == .library {
                        ProfileAvatarView(avatar: profiles.activeProfile?.avatar ?? .crimson, size: 23)
                    } else {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: primary ? .regular : .light))
                            .foregroundStyle(AppTheme.foreground.opacity(primary ? 1 : restingOpacity))
                    }
                }
                .frame(width: 24, height: 24)
                .scaleEffect(primary && dragCenter != nil && !reduceMotion ? 1.06 : 1)
                .accessibilityHidden(true)
                Text(tab.title).font(.system(size: labelSize, weight: primary ? .semibold : .medium))
                    .foregroundStyle(AppTheme.foreground.opacity(primary ? 1 : restingOpacity))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(LiquidGlassTabInteractionStyle(
            coordinateSpace: Self.coordinateSpace,
            changed: { updateTouch(tab, value: $0, width: width) },
            ended: { finishTouch(tab, value: $0, width: width) },
            cancelled: { if touch?.origin == tab { cancelTouch(animated: true) } }))
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab == .library ? "Profile: \(profiles.activeProfile?.name ?? "My profile"), \(profiles.activeProfile?.avatar.title ?? "Crimson") avatar" : "")
        // Scrubbing only previews; VoiceOver reports the committed page.
        .accessibilityAddTraits(tab == selection ? [.isSelected] : [])
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }

    private func tabCenter(_ tab: AppTab, width: CGFloat) -> CGFloat {
        let index = AppTab.allCases.firstIndex(of: tab) ?? 0
        return (CGFloat(index) + 0.5) * width / CGFloat(AppTab.allCases.count)
    }

    private func tabAt(_ center: CGFloat, width: CGFloat) -> AppTab {
        let index = min(AppTab.allCases.count - 1, max(0, Int(center / (width / CGFloat(AppTab.allCases.count)))))
        return AppTab.allCases[index]
    }

    private func updateTouch(_ tab: AppTab, value: DragGesture.Value, width: CGFloat) {
        guard !profilesOpen, scenePhase == .active else { return }
        if touch == nil {
            let started = BarTouch(origin: tab)
            touch = started
            if tab == .library { armProfileHold(started.id) }
        }
        guard var active = touch, active.origin == tab, !active.consumed, !active.cancelled else { return }
        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        if !active.dragging && vertical > 18 && vertical > horizontal {
            active.cancelled = true; touch = active; holdTask?.cancel(); holdTask = nil
            return
        }
        guard active.dragging || horizontal > 6 else { return }
        holdTask?.cancel(); holdTask = nil
        active.dragging = true
        let halfCell = width / CGFloat(AppTab.allCases.count) / 2
        let center = min(width - halfCell, max(halfCell, tabCenter(tab, width: width) + value.translation.width))
        let candidate = tabAt(center, width: width)
        if candidate != (preview ?? selection) { AppHaptics.tap(.selection) }
        // No implicit animation here: the lens follows the thumb one-to-one.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { touch = active; dragCenter = center; preview = candidate }
    }

    /// Returns true only for a short tap, allowing the primitive button to fire.
    private func finishTouch(_ tab: AppTab, value: DragGesture.Value, width: CGFloat) -> Bool {
        holdTask?.cancel(); holdTask = nil
        guard let active = touch, active.origin == tab else { return false }
        touch = nil
        guard !active.consumed, !active.cancelled, !profilesOpen,
              value.location.y >= -44, value.location.y <= height + 44 else {
            settleLens(); return false
        }
        if active.dragging {
            let target = tabAt(dragCenter ?? tabCenter(tab, width: width), width: width)
            select(target, feedback: false)
            settleLens()
            return false
        }
        settleLens()
        return true
    }

    private func select(_ tab: AppTab, feedback: Bool) {
        guard tab != selection else { return }
        if feedback { AppHaptics.tap(.selection) }
        // Root content changes immediately, including taps during a previous
        // lens settlement; only this bar's lens can spring to its resting slot.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { selection = tab }
    }

    private func settleLens() {
        withAnimation(settlingAnimation) { dragCenter = nil; preview = nil }
    }

    private func cancelTouch(animated: Bool) {
        holdTask?.cancel(); holdTask = nil; touch = nil
        if animated { settleLens() }
        else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { dragCenter = nil; preview = nil }
        }
    }

    private func armProfileHold(_ id: UUID) {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard var active = touch, active.id == id, !active.dragging,
                  !active.cancelled, scenePhase == .active else { return }
            active.consumed = true; touch = active
            openProfiles()
        }
    }

    private func openProfiles() {
        guard !profilesOpen, profiles.canEditProfiles else { return }
        pendingProfile = nil; pendingOwner = nil
        AppHaptics.tap()
        profilesOpen = true
    }

    private func finishProfileSelection() {
        guard let id = pendingProfile else { return }
        let owner = pendingOwner
        pendingProfile = nil; pendingOwner = nil
        guard scenePhase == .active, profiles.canEditProfiles, profiles.ownerUID == owner,
              profiles.profiles.contains(where: { $0.id == id }) else { return }
        onSelectProfile(id)
    }

    private struct BarTouch {
        let id = UUID()
        let origin: AppTab
        var dragging = false
        var consumed = false
        var cancelled = false
    }
}

/// A single contact owns tap, drag and hold outcomes, preventing a tab's release
/// action from overriding the tab chosen by a scrub or a profile hold.
private struct LiquidGlassTabInteractionStyle: PrimitiveButtonStyle {
    let coordinateSpace: String
    let changed: (DragGesture.Value) -> Void
    let ended: (DragGesture.Value) -> Bool
    let cancelled: () -> Void
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassTouchSurface(label: configuration.label, coordinateSpace: coordinateSpace,
            enabled: enabled, changed: changed, ended: ended, cancelled: cancelled,
            trigger: configuration.trigger)
    }
}

private struct LiquidGlassTouchSurface<Label: View>: View {
    let label: Label
    let coordinateSpace: String
    let enabled: Bool
    let changed: (DragGesture.Value) -> Void
    let ended: (DragGesture.Value) -> Bool
    let cancelled: () -> Void
    let trigger: () -> Void
    @GestureState private var contact = false
    @State private var contactGeneration = 0

    var body: some View {
        label
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
                .updating($contact) { _, state, _ in state = true }
                .onChanged { if enabled { changed($0) } }
                .onEnded { value in if enabled && ended(value) { trigger() } })
            .onChange(of: contact) { _, active in
                if active { contactGeneration += 1 }
                else {
                    let generation = contactGeneration
                    // GestureState can reset before onEnded. Let the release
                    // handler commit first; only a genuinely cancelled contact
                    // should clear its pending tap or profile selection.
                    DispatchQueue.main.async {
                        guard !contact, contactGeneration == generation else { return }
                        cancelled()
                    }
                }
            }
            .accessibilityAction { if enabled { trigger() } }
    }
}

private struct LiquidGlassBarSurface: ViewModifier {
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let dark: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(AppTheme.canvas, in: Capsule())
                .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(0.18), lineWidth: 0.8).allowsHitTesting(false) }
        } else {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(!reduceMotion), in: Capsule())
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(dark ? 0.14 : 0.1), lineWidth: 0.7).allowsHitTesting(false) }
            }
        }
    }
}

private struct LiquidGlassQuickProfilePicker: View {
    let select: (AppProfile) -> Void
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var pickerSize: CGSize = .zero
    @State private var rowsHeight: CGFloat = 0
    @State private var contactOrigin: UUID?
    @State private var pressedProfile: UUID?
    @State private var hoveredProfile: UUID?
    private static let coordinateSpace = "streamify-quick-profile-choices"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Switch profile").font(.headline).padding(.horizontal, 10).padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            // One rendered row list owns hit-test geometry. ViewThatFits with
            // two copies of this list can publish the same profile frames
            // from both its fitted and rejected candidate layouts.
            ScrollView {
                profileRows.background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: LiquidGlassProfileRowsHeightKey.self, value: geometry.size.height)
                    }
                }
            }
            .frame(height: min(300, rowsHeight > 0 ? rowsHeight : max(60, CGFloat(profiles.profiles.count) * 64 - 4)))
            .scrollDisabled(rowsHeight <= 300)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .padding(10).frame(width: dynamicTypeSize.isAccessibilitySize ? 300 : 264)
        .foregroundStyle(AppTheme.foreground)
        .coordinateSpace(name: Self.coordinateSpace)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: LiquidGlassPickerSizeKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(LiquidGlassProfileFramesKey.self) { rowFrames = $0 }
        .onPreferenceChange(LiquidGlassPickerSizeKey.self) { pickerSize = $0 }
        .onPreferenceChange(LiquidGlassProfileRowsHeightKey.self) { rowsHeight = $0 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelContact() } }
        .onDisappear { cancelContact(); hoveredProfile = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-profile-picker")
    }

    private var profileRows: some View {
        VStack(spacing: 4) {
            ForEach(profiles.profiles) { profile in
                let current = profile.id == profiles.activeProfile?.id
                let highlighted = (contactOrigin == nil ? hoveredProfile : pressedProfile) == profile.id
                Button { select(profile) } label: {
                    HStack(spacing: 12) {
                        ProfileAvatarView(avatar: profile.avatar, size: 44)
                        Text(profile.name).font(.subheadline.weight(highlighted ? .bold : .semibold)).lineLimit(2)
                        Spacer(minLength: 4)
                        if current {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .medium))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(AppTheme.foreground.opacity(highlighted ? 0.15 : current ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.foreground.opacity(highlighted ? 0.16 : 0), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
                    .scaleEffect(highlighted && !reduceMotion ? 1.015 : 1)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: LiquidGlassProfileFramesKey.self,
                                value: [profile.id: geometry.frame(in: .named(Self.coordinateSpace))])
                        }
                    }
                }
                .buttonStyle(LiquidGlassTabInteractionStyle(coordinateSpace: Self.coordinateSpace,
                    changed: { updateContact(origin: profile.id, location: $0.location) },
                    ended: { value in
                        if abs(value.translation.width) < 6 && abs(value.translation.height) < 6 {
                            // A short tap already identifies its real Button;
                            // do not require a preference-frame lookup to fire.
                            cancelContact()
                            return true
                        }
                        finishContact(origin: profile.id, location: value.location)
                        return false
                    }, cancelled: { if contactOrigin == profile.id { cancelContact() } }))
                // Pointer hover is only visual. An iPhone finger previews while
                // pressed and commits one choice when it is released in a row.
                .onHover { hovering in
                    if hovering { hoveredProfile = profile.id }
                    else if hoveredProfile == profile.id { hoveredProfile = nil }
                }
                .accessibilityLabel(profile.name)
                .accessibilityValue(current ? "Current profile" : "Switch to this profile")
                .accessibilityAddTraits(current ? [.isSelected] : [])
                .accessibilityIdentifier("quick-profile-\(profile.id.uuidString)")
            }
        }
    }

    private func profileAt(_ location: CGPoint) -> UUID? {
        guard location.x >= 0, location.y >= 0,
              location.x <= pickerSize.width, location.y <= pickerSize.height else { return nil }
        return rowFrames.first { $0.value.contains(location) }?.key
    }

    private func updateContact(origin: UUID, location: CGPoint) {
        guard scenePhase == .active else { return }
        if contactOrigin == nil { contactOrigin = origin; hoveredProfile = nil }
        guard contactOrigin == origin else { return }
        let target = profileAt(location)
        if pressedProfile != nil, target != nil, pressedProfile != target { AppHaptics.tap(.selection) }
        pressedProfile = target
    }

    private func finishContact(origin: UUID, location: CGPoint) {
        // onEnded belongs to the row that received this contact. GestureState
        // can clear the visual contact before this callback; that must not
        // discard a valid release. Cancelled gestures never deliver onEnded.
        guard profiles.profiles.contains(where: { $0.id == origin }) else { cancelContact(); return }
        let target = profileAt(location)
        cancelContact()
        guard let target, let profile = profiles.profiles.first(where: { $0.id == target }) else { return }
        select(profile)
    }

    private func cancelContact() {
        contactOrigin = nil; pressedProfile = nil
    }
}

private struct LiquidGlassProfileFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct LiquidGlassPickerSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct LiquidGlassProfileRowsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
