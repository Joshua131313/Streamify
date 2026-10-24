import SwiftUI

/// The chooser stays usable with no catalog key or network connection. Artwork
/// is decorative; profile selection and editing use only the local store.
@MainActor
struct ProfileChooserView: View {
    var isSwitching = false
    var onCancel: (() -> Void)? = nil
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var preferredAvatarSize: CGFloat = 104
    @State private var editing = false
    @State private var editor: ProfileEditorTarget?
    @State private var featured: MediaItem?

    private var columnCount: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 3 }
    private var nextAvatar: ProfileAvatar {
        ProfileAvatar.allCases.first { candidate in !store.profiles.contains { $0.avatar == candidate } } ?? .crimson
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                VStack(spacing: 0) {
                    header
                    profileScroll(size: geometry.size)
                }
            }
            .background {
                GeometryReader { artwork in
                    ProfileCinematicBackdrop(media: featured, size: artwork.size)
                }.ignoresSafeArea()
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-chooser")
        .sheet(item: $editor) { target in
            ProfileEditorView(profile: target.profile, initialAvatar: nextAvatar)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .task(id: settings.tmdbToken) { await loadArtwork() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: editing)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image("streamify-logo").resizable().scaledToFit().frame(width: 30, height: 34)
                .accessibilityHidden(true)
            Text("STREAMIFY").font(.system(size: 16, weight: .bold, design: .rounded)).tracking(2)
            Spacer(minLength: 12)
            if isSwitching, let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityLabel("Cancel switching profiles")
                .accessibilityIdentifier("profile-switch-cancel")
            }
        }
        .frame(height: 48).padding(.horizontal, 24).padding(.vertical, 10)
    }

    private func profileScroll(size: CGSize) -> some View {
        let width = max(1, min(size.width - 40, 600))
        let tileWidth = max(1, (width - CGFloat(columnCount - 1) * 18) / CGFloat(columnCount))
        let avatarSize = min(tileWidth, preferredAvatarSize)
        return ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: size.width > size.height ? 16 : 72)
                chooserContent(avatarSize: avatarSize, tileWidth: tileWidth)
                    .frame(width: width)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, size.height - 68))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func chooserContent(avatarSize: CGFloat, tileWidth: CGFloat) -> some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text(editing ? "Edit profiles" : "Choose your profile")
                    .font(.title.weight(.bold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(editing ? "Make each profile your own." : "Your list. Your history. Your next watch.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.68)).multilineTextAlignment(.center)
            }
            profileGrid(avatarSize: avatarSize, tileWidth: tileWidth)
            Button { editing.toggle() } label: {
                Label(editing ? "Done" : "Edit profiles", systemImage: editing ? "checkmark" : "pencil")
            }
            .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 210)
            .accessibilityIdentifier("profile-manage")
            Text("Profiles on this iPhone").font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func profileGrid(avatarSize: CGFloat, tileWidth: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: 18, alignment: .top), count: columnCount), spacing: 24) {
            ForEach(store.profiles) { profile in
                ProfileChoiceTile(profile: profile, size: avatarSize, editing: editing,
                    selected: store.activeProfile?.id == profile.id) {
                    if editing { editor = ProfileEditorTarget(profile: profile) }
                    else { store.select(profile.id) }
                }
            }
            if store.profiles.count < 5 {
                Button { editor = ProfileEditorTarget(profile: nil) } label: {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: avatarSize * 0.2, style: .continuous)
                            .fill(.white.opacity(0.065))
                            .overlay {
                                RoundedRectangle(cornerRadius: avatarSize * 0.2, style: .continuous)
                                    .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                Image(systemName: "plus").font(.system(size: avatarSize * 0.28, weight: .light))
                            }
                            .frame(width: avatarSize, height: avatarSize)
                        Text("Add profile").font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, alignment: .top)
                }
                .buttonStyle(HapticCardButtonStyle(cornerRadius: 18))
                .accessibilityLabel("Add profile").accessibilityIdentifier("profile-add")
            }
        }
    }

    @MainActor private func loadArtwork() async {
        featured = nil
        guard !settings.tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let page = try await settings.client.catalog(path: "trending/all/day")
            try Task.checkCancellation()
            featured = page.items.first { !$0.backdropPath.isEmpty } ?? page.items.first { !$0.posterPath.isEmpty }
        } catch { /* Bundled artwork remains visible; profiles never wait for a catalog. */ }
    }
}

private struct ProfileEditorTarget: Identifiable {
    let id = UUID()
    let profile: AppProfile?
}

private struct ProfileCinematicBackdrop: View {
    let media: MediaItem?
    let size: CGSize
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055)
            Image("collection-lord-of-the-rings").resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
            if let url = media?.heroBackdropURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                    }
                }
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0),
                .init(color: .black.opacity(0.36), location: 0.28),
                .init(color: .black.opacity(0.84), location: 0.58),
                .init(color: Color(red: 0.035, green: 0.04, blue: 0.055), location: 1)],
                startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
        }
        .frame(width: size.width, height: size.height).clipped()
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct ProfileChoiceTile: View {
    let profile: AppProfile
    let size: CGFloat
    let editing: Bool
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ProfileAvatarView(avatar: profile.avatar, size: size)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                            .strokeBorder(.white.opacity(selected && !editing ? 0.9 : 0.15), lineWidth: selected && !editing ? 2 : 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if editing {
                            Image(systemName: "pencil").font(.system(size: 12, weight: .semibold))
                                .frame(width: 30, height: 30).background(.black.opacity(0.88), in: Circle())
                                .overlay { Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                                .offset(x: 5, y: 5)
                        }
                    }
                Text(profile.name).font(.subheadline.weight(.medium)).lineLimit(2)
                    .multilineTextAlignment(.center).frame(minHeight: 22, alignment: .top)
            }.frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(HapticCardButtonStyle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(editing ? "Edit \(profile.name)" : profile.name)
        .accessibilityHint(editing ? "Change this profile’s name or avatar." : "Open this profile.")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("profile-tile-\(profile.id.uuidString)")
    }
}

/// Custom SF-symbol avatar compositions; no third-party profile graphics.
struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                Circle().fill(.white.opacity(0.13)).frame(width: size * 0.75, height: size * 0.75)
                    .offset(x: -size * 0.25, y: -size * 0.3)
            }
            .overlay {
                Image(systemName: palette.symbol).font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94)).shadow(color: .black.opacity(0.12), radius: 2, y: 2)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .accessibilityHidden(true)
    }
    private var palette: (top: Color, bottom: Color, symbol: String) {
        switch avatar {
        case .crimson: return (Color(red: 0.72, green: 0.22, blue: 0.3), Color(red: 0.38, green: 0.08, blue: 0.17), "cat.fill")
        case .ocean: return (Color(red: 0.22, green: 0.57, blue: 0.76), Color(red: 0.06, green: 0.24, blue: 0.43), "fish.fill")
        case .forest: return (Color(red: 0.32, green: 0.59, blue: 0.43), Color(red: 0.1, green: 0.28, blue: 0.23), "tortoise.fill")
        case .violet: return (Color(red: 0.56, green: 0.4, blue: 0.76), Color(red: 0.25, green: 0.15, blue: 0.43), "bird.fill")
        case .gold: return (Color(red: 0.78, green: 0.55, blue: 0.22), Color(red: 0.47, green: 0.28, blue: 0.08), "hare.fill")
        case .slate: return (Color(red: 0.42, green: 0.5, blue: 0.6), Color(red: 0.2, green: 0.26, blue: 0.35), "dog.fill")
        }
    }
}

@MainActor
private struct ProfileEditorView: View {
    let profile: AppProfile?
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var avatar: ProfileAvatar
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(profile: AppProfile?, initialAvatar: ProfileAvatar) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _avatar = State(initialValue: profile?.avatar ?? initialAvatar)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ProfileAvatarView(avatar: avatar, size: 88).frame(maxWidth: .infinity).padding(.top, 12)
                    nameInput
                    avatarPicker
                    Button(action: save) { Text("Save profile").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("profile-save")
                    if profile != nil { deleteAction }
                }.padding(24).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
            .navigationTitle(profile == nil ? "Add profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("profile-editor-cancel")
                }
            }
            .alert("Couldn’t update profiles", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "Please try again.") }
            .confirmationDialog("Delete \(profile?.name ?? "profile")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete profile", role: .destructive, action: delete).accessibilityIdentifier("profile-delete-confirm")
                Button("Cancel", role: .cancel) { }
            } message: { Text("You can’t undo this action.") }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-editor")
    }

    private var nameInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile name").font(.subheadline.weight(.semibold))
            TextField("Name", text: $name).textContentType(.nickname).textInputAutocapitalization(.words)
                .autocorrectionDisabled().submitLabel(.done).focused($nameFocused)
                .padding(14).streamifyControlSurface()
                .accessibilityLabel("Profile name").accessibilityIdentifier("profile-name-field")
                .onSubmit { if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { save() } }
            Text("Up to 24 characters.").font(.caption).foregroundStyle(AppTheme.muted)
        }
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose an avatar").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 16)], spacing: 16) {
                ForEach(ProfileAvatar.allCases) { candidate in
                    Button { avatar = candidate } label: {
                        ProfileAvatarView(avatar: candidate, size: 64)
                            .padding(5)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(avatar == candidate ? .white : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel("\(candidate.rawValue.capitalized) avatar")
                    .accessibilityAddTraits(avatar == candidate ? .isSelected : [])
                    .accessibilityIdentifier("profile-avatar-\(candidate.rawValue)")
                }
            }
        }
    }

    private var deleteAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Delete profile", role: .destructive) { nameFocused = false; confirmDelete = true }
                .buttonStyle(SecondaryButtonStyle()).disabled(store.profiles.count <= 1)
                .accessibilityIdentifier("profile-delete")
            if store.profiles.count <= 1 {
                Text("Keep at least one profile.").font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func save() {
        nameFocused = false
        do {
            if let profile { try store.update(id: profile.id, name: name, avatar: avatar) }
            else { try store.add(name: name, avatar: avatar) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() {
        guard let profile else { return }
        do { try store.remove(profile.id); dismiss() }
        catch { error = error.localizedDescription }
    }
}
