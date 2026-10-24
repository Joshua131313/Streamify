import SwiftUI

struct SportsChatView: View {
    let game: SportsGame
    @StateObject private var chat = SportsChatStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var retry = 0
    @State private var nearBottom = true
    @State private var viewportHeight: CGFloat = 300
    @FocusState private var composing: Bool

    private var room: String? { SportsChatContract.room(league: game.league, away: game.away.abbreviation, home: game.home.abbreviation) }
    private var observationID: String { "\(room ?? "invalid")|\(scenePhase == .active)|\(retry)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right").font(.title3)
                    .foregroundStyle(AppTheme.muted).frame(width: 44, height: 44)
                    .background(AppTheme.panel, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Game chat").font(.title3.bold())
                    Text("Join the conversation as a guest").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
            }
            if chat.loading { ProgressView().frame(maxWidth: .infinity).padding(16) }
            if let error = chat.error {
                errorRow(error) { retry += 1 }
            }
            thread
            composer
            if let error = chat.actionError {
                errorRow(error) { Task { await chat.retryAction() } }
                    .accessibilityIdentifier("sports-chat-action-error")
            }
            Text("Public chat · Be kind to fellow fans").font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .foregroundStyle(AppTheme.foreground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-chat")
        .task(id: observationID) { chat.listen(room: room, active: scenePhase == .active) }
        .onChange(of: chat.draft) { _, value in
            let limited = SportsChatContract.limitDraft(value)
            if limited != value { chat.draft = limited }
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat.messages) { message in messageBubble(message) }
                        if !chat.loading, chat.error == nil, chat.messages.isEmpty {
                            VStack(spacing: 6) {
                                Text("Be the first to say hello").font(.subheadline.weight(.semibold))
                                Text("Share the moment with other fans.").font(.caption).foregroundStyle(AppTheme.muted)
                            }.frame(maxWidth: .infinity).padding(.vertical, 42)
                        }
                        Color.clear.frame(height: 1).id("sports-chat-bottom")
                    }.padding(12)
                        // Measure the content container, which remains mounted
                        // while older rows are visible. A lazy bottom sentinel
                        // can disappear offscreen and falsely report zero.
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: SportsChatBottom.self,
                                value: geometry.frame(in: .named("sports-chat-scroll")).maxY)
                        })
                }
                .coordinateSpace(name: "sports-chat-scroll")
                .scrollDismissesKeyboard(.interactively)
                .frame(height: 300)
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { viewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
                })
                .onPreferenceChange(SportsChatBottom.self) { bottom in nearBottom = bottom <= viewportHeight + 60 }
                .onChange(of: chat.messages.last?.id) { old, _ in
                    guard nearBottom || old == nil else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("sports-chat-bottom", anchor: .bottom) }
                    }
                }
                if !nearBottom, !chat.messages.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("sports-chat-bottom", anchor: .bottom) }
                    } label: {
                        Label("Latest messages", systemImage: "arrow.down").font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-chat-latest")
                }
            }
        }
        .background(AppTheme.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.foreground.opacity(0.07), lineWidth: 1))
    }

    private func messageBubble(_ message: SportsChatMessage) -> some View {
        let own = !message.uid.isEmpty && message.uid == chat.userID
        return HStack {
            if own { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Button {
                        chat.draft = SportsChatContract.limitDraft(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines) + " @\(message.handle) ")
                        composing = true
                    } label: { Text(own ? "You" : message.sender).font(.caption.weight(.semibold)).lineLimit(1) }
                        .buttonStyle(HapticPlainButtonStyle())
                    Spacer(minLength: 0)
                    if message.pending { Text("Sending…").font(.caption2) }
                    else if let time = message.sentAt { Text(time, format: .dateTime.hour().minute()).font(.caption2) }
                }.foregroundStyle(AppTheme.muted)
                if let quote = message.reply {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reply to \(quote.sender)").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
                        Text(quote.message).font(.caption).lineLimit(2)
                    }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
                Text(message.text).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { chat.reply = message.quote; composing = true } label: {
                        Image(systemName: "arrowshape.turn.up.left").frame(width: 32, height: 32)
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Reply to \(message.sender)")
                    Menu {
                        ForEach(SportsChatContract.reactions, id: \.self) { emoji in
                            Button(emoji) { AppHaptics.tap(); Task { await chat.react(messageID: message.id, emoji: emoji) } }
                        }
                    } label: { Image(systemName: "face.smiling").frame(width: 32, height: 32) }
                        .accessibilityLabel("React to \(message.sender)")
                    Spacer(minLength: 0)
                }.font(.caption).foregroundStyle(AppTheme.muted).disabled(message.pending)
                if !message.votes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(SportsChatContract.reactions.filter { message.votes.values.contains($0) }, id: \.self) { emoji in
                                Button { Task { await chat.react(messageID: message.id, emoji: emoji) } } label: {
                                    Text("\(emoji) \(message.votes.values.filter { $0 == emoji }.count)").font(.caption)
                                        .padding(.horizontal, 7).padding(.vertical, 6)
                                        .background(AppTheme.foreground.opacity(message.votes[chat.userID ?? ""] == emoji ? 0.16 : 0.05), in: Capsule())
                                }.buttonStyle(HapticPlainButtonStyle())
                            }
                        }
                    }.disabled(message.pending)
                }
            }
            .padding(12)
            .frame(maxWidth: 310, alignment: .leading)
            .background(AppTheme.foreground.opacity(own ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 14))
            if !own { Spacer(minLength: 24) }
        }.accessibilityIdentifier("sports-chat-message-\(message.id)")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reply = chat.reply {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Replying to \(reply.sender)").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                        Text(reply.message).font(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { chat.reply = nil } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                        .buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Cancel reply")
                }.padding(.leading, 4)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Say something…", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4).font(.subheadline).focused($composing)
                    .padding(12).background(AppTheme.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .tint(AppTheme.foreground).disabled(chat.sending || room == nil)
                    .accessibilityIdentifier("sports-chat-composer")
                Button { Task { await chat.send() } } label: {
                    Group {
                        if chat.sending { ProgressView().tint(AppTheme.canvas) }
                        else { Image(systemName: "arrow.up").font(.headline) }
                    }.frame(width: 44, height: 44)
                        .foregroundStyle(AppTheme.canvas)
                        .background(AppTheme.foreground.opacity(canSend ? 1 : 0.25), in: Circle())
                }.buttonStyle(HapticPlainButtonStyle()).disabled(!canSend)
                    .accessibilityLabel("Send message").accessibilityIdentifier("sports-chat-send")
            }
            if chat.draft.utf16.count >= 900 {
                Text("\(chat.draft.utf16.count)/1,000").font(.caption2).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(10).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var canSend: Bool { room != nil && !chat.sending && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func errorRow(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(AppTheme.muted)
            Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry).font(.caption.weight(.semibold)).buttonStyle(HapticPlainButtonStyle()).disabled(chat.sending)
        }.padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SportsChatBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
