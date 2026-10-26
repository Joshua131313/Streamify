import SwiftUI

struct FloatingNavigation: View {
    @Binding var selection: AppTab
    let onSelectProfile: (UUID) -> Void
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var selectedTabAnimation
    @State private var selectionFeedback = 0
    @State private var profilesOpen = false
    @State private var pendingProfile: UUID?
    @State private var pendingOwner: String?
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9.5

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if tab == .library {
                    tabButton(tab)
                        .buttonStyle(ProfileTabInteractionStyle(onHold: openProfiles))
                        .accessibilityHint("Touch and hold to switch profiles.")
                        .accessibilityAction(named: Text("Switch profiles"), openProfiles)
                        .popover(isPresented: $profilesOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                            QuickProfilePicker { profile in
                                guard profilesOpen, pendingProfile == nil else { return }
                                AppHaptics.tap(.primary)
                                if profile.id != profiles.activeProfile?.id {
                                    pendingProfile = profile.id
                                    pendingOwner = profiles.ownerUID
                                }
                                profilesOpen = false
                            }
                            .environmentObject(profiles)
                            .presentationCompactAdaptation(.popover)
                            .onDisappear(perform: finishProfileSelection)
                        }
                } else {
                    tabButton(tab).buttonStyle(.plain)
                }
            }
        }
        .padding(3).frame(maxWidth: 400)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay { Capsule().fill(AppTheme.canvas.opacity(colorScheme == .dark ? 0.3 : 0.55)) }
        }
        .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(colorScheme == .dark ? 0.14 : 0.1), lineWidth: 0.7) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 12, y: 5)
        .animation(selectionAnimation, value: selection)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .padding(.horizontal, 50).padding(.top, 4)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pendingProfile = nil; pendingOwner = nil; profilesOpen = false }
        }
        .onDisappear { pendingProfile = nil; pendingOwner = nil; profilesOpen = false }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            guard !selected else { return }
            selectionFeedback += 1
            selection = tab
        } label: {
            VStack(spacing: 1) {
                ZStack {
                    if tab == .library {
                        ProfileAvatarView(avatar: profiles.activeProfile?.avatar ?? .crimson, size: 23)
                    } else {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .light))
                            .foregroundStyle(AppTheme.foreground.opacity(selected ? 1 : 0.55))
                    }
                }
                .frame(width: 24, height: 24)
                .scaleEffect(selected && !reduceMotion ? 1.06 : 1)
                .accessibilityHidden(true)
                Text(tab.title).font(.system(size: labelSize, weight: selected ? .semibold : .medium))
                    .foregroundStyle(AppTheme.foreground.opacity(selected ? 1 : 0.55))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .scaleEffect(selected && !reduceMotion ? 1.02 : 1)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 50)
            .background {
                if selected {
                    Capsule().fill(AppTheme.foreground.opacity(colorScheme == .dark ? 0.12 : 0.08))
                        .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(0.06), lineWidth: 0.5) }
                        .matchedGeometryEffect(id: "selected-tab", in: selectedTabAnimation)
                        .padding(.horizontal, 2)
                }
            }
            .contentShape(Capsule())
        }
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab == .library ? "Profile: \(profiles.activeProfile?.name ?? "My profile"), \(profiles.activeProfile?.avatar.title ?? "Crimson") avatar" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }

    private func openProfiles() {
        guard !profilesOpen, profiles.canEditProfiles else { return }
        pendingProfile = nil
        pendingOwner = nil
        AppHaptics.tap()
        profilesOpen = true
    }

    private func finishProfileSelection() {
        guard let id = pendingProfile else { return }
        let owner = pendingOwner
        pendingProfile = nil
        pendingOwner = nil
        guard scenePhase == .active, profiles.canEditProfiles,
              profiles.ownerUID == owner,
              profiles.profiles.contains(where: { $0.id == id }) else { return }
        onSelectProfile(id)
    }
}

/// One gesture owns both outcomes: releasing a successful hold cannot also
/// trigger My list. Accessibility activation keeps the normal button action.
private struct ProfileTabInteractionStyle: PrimitiveButtonStyle {
    let onHold: () -> Void
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .gesture(LongPressGesture(minimumDuration: 0.45, maximumDistance: 14)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    guard enabled else { return }
                    switch result {
                    case .first(true): onHold()
                    case .second: configuration.trigger()
                    default: break
                    }
                })
            .accessibilityAction { if enabled { configuration.trigger() } }
    }
}

private struct QuickProfilePicker: View {
    let select: (AppProfile) -> Void
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Switch profile")
                .font(.headline).padding(.horizontal, 10).padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .vertical) {
                profileRows
                ScrollView { profileRows }.frame(maxHeight: 300)
            }
        }
        .padding(10)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 300 : 264)
        .foregroundStyle(AppTheme.foreground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-profile-picker")
    }

    private var profileRows: some View {
        VStack(spacing: 4) {
            ForEach(profiles.profiles) { profile in
                let current = profile.id == profiles.activeProfile?.id
                Button { select(profile) } label: {
                    HStack(spacing: 12) {
                        ProfileAvatarView(avatar: profile.avatar, size: 44)
                        Text(profile.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer(minLength: 4)
                        if current {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .medium))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(AppTheme.foreground.opacity(current ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(profile.name)
                .accessibilityValue(current ? "Current profile" : "Switch to this profile")
                .accessibilityAddTraits(current ? [.isSelected] : [])
                .accessibilityIdentifier("quick-profile-\(profile.id.uuidString)")
            }
        }
    }
}
