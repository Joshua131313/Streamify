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
    @ScaledMetric(relativeTo: .body) private var preferredAvatarSize: CGFloat = 76
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
        ZStack {
            HStack(spacing: 6) {
                Image("streamify-logo").resizable().scaledToFit().frame(width: 22, height: 25)
                    .accessibilityHidden(true)
                Text("STREAMIFY").font(.system(size: 11, weight: .semibold)).tracking(2)
            }
            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            if isSwitching, let onCancel {
                HStack {
                    Spacer()
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
        }
        .frame(height: 44).padding(.horizontal, 20).padding(.vertical, 4)
    }

    private func profileScroll(size: CGSize) -> some View {
        let width = max(1, min(size.width - 56, 460))
        let tileWidth = max(1, (width - CGFloat(columnCount - 1) * 18) / CGFloat(columnCount))
        let avatarSize = min(tileWidth, preferredAvatarSize)
        return ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: size.width > size.height ? 16 : max(80, size.height * 0.28))
                featuredTitle
                    .padding(.horizontal, 28)
                    .padding(.bottom, size.width > size.height ? 20 : 32)
                chooserContent(avatarSize: avatarSize, tileWidth: tileWidth)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                    .background {
                        ProfilePanelShape()
                            .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.14, blue: 0.14).opacity(0.5),
                                Color(red: 0.17, green: 0.14, blue: 0.14)], startPoint: .top, endPoint: .bottom))
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, size.height - 52))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("profile-chooser-scroll")
    }

    private func chooserContent(avatarSize: CGFloat, tileWidth: CGFloat) -> some View {
        VStack(spacing: 22) {
                Text(editing ? "Edit profiles" : "Choose your profile")
                    .font(.body).foregroundStyle(.white.opacity(0.86)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            profileGrid(avatarSize: avatarSize, tileWidth: tileWidth)
        }
    }

    private var featuredTitle: some View {
        VStack(spacing: 9) {
            Text(featured == nil ? "FEATURED COLLECTION" : "FEATURED ON STREAMIFY")
                .font(.caption2.weight(.medium)).tracking(2)
                .foregroundStyle(Color(red: 0.91, green: 0.83, blue: 0.73))
            Text(featured?.title ?? "The Hobbit")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .multilineTextAlignment(.center).lineLimit(3)
                .shadow(color: .black.opacity(0.65), radius: 12, y: 2)
        }
        .accessibilityHidden(true)
    }

    private func profileGrid(avatarSize: CGFloat, tileWidth: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: 18, alignment: .top), count: columnCount), spacing: 22) {
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
                            .fill(.white.opacity(0.09))
                            .overlay {
                                Image(systemName: "plus").font(.system(size: avatarSize * 0.28, weight: .light))
                            }
                            .frame(width: avatarSize, height: avatarSize)
                        Text("Add profile").font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, alignment: .top)
                }
                .buttonStyle(HapticCardButtonStyle(cornerRadius: 18))
                .accessibilityLabel("Add profile").accessibilityIdentifier("profile-add")
            }
            Button { editing.toggle() } label: {
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: avatarSize * 0.2, style: .continuous)
                        .fill(Color(red: 0.31, green: 0.25, blue: 0.26))
                        .overlay {
                            Image(systemName: editing ? "checkmark" : "pencil")
                                .font(.system(size: avatarSize * 0.35, weight: .light))
                        }
                        .frame(width: avatarSize, height: avatarSize)
                    Text(editing ? "Done" : "Edit").font(.subheadline.weight(.medium))
                        .frame(minHeight: 22, alignment: .top)
                }.frame(maxWidth: .infinity, alignment: .top)
            }
            .buttonStyle(HapticCardButtonStyle(cornerRadius: 16))
            .accessibilityLabel(editing ? "Done editing profiles" : "Edit profiles")
            .accessibilityIdentifier("profile-manage")
        }
    }

    @MainActor private func loadArtwork() async {
        guard !settings.tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let page = try await settings.client.catalog(path: "trending/all/day")
            try Task.checkCancellation()
            featured = page.items.first { !$0.posterPath.isEmpty }
        } catch { /* Bundled artwork remains visible; profiles never wait for a catalog. */ }
    }
}

private struct ProfilePanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 16))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 16),
                          control: CGPoint(x: rect.midX, y: rect.minY - 16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
            Color(red: 0.105, green: 0.09, blue: 0.095)
            Image("collection-hobbit").resizable().scaledToFill()
                .frame(width: size.width, height: size.height * 0.8, alignment: .top).clipped()
                .frame(maxHeight: .infinity, alignment: .top)
            if let url = size.width > size.height ? media?.heroBackdropURL : media?.heroPosterURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                            .frame(width: size.width, height: size.height * 0.8, alignment: .top).clipped()
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.22), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.36),
                .init(color: Color(red: 0.105, green: 0.09, blue: 0.095).opacity(0.65), location: 0.55),
                .init(color: Color(red: 0.105, green: 0.09, blue: 0.095), location: 0.78)],
                startPoint: .top, endPoint: .bottom)
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
        Button {
            AppHaptics.tap()
            action()
        } label: {
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
        .buttonStyle(CardPressedButtonStyle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(editing ? "Edit \(profile.name)" : profile.name)
        .accessibilityHint(editing ? "Change this profile’s name or avatar." : "Open this profile.")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("profile-tile-\(profile.id.uuidString)")
    }
}

/// Original 3D artwork, bundled so profile selection also works offline.
struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    let size: CGFloat
    var body: some View {
        Image(avatar.artworkName).resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
            .accessibilityHidden(true)
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
            .accessibilityIdentifier("profile-editor-scroll")
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
                    .accessibilityLabel("\(candidate.title) avatar")
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
        catch { self.error = error.localizedDescription }
    }
}
