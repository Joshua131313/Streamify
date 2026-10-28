import SwiftUI

struct SportsGameChatScreen: View {
    let game: SportsGame
    var sceneIsActive: Bool? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SportsChatView(game: game, sceneIsActive: sceneIsActive).padding(.horizontal, 16).padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(AppTheme.canvas)
                .navigationTitle("Game chat").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32).contentShape(Circle())
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Close chat")
                        .accessibilityIdentifier("sports-chat-close")
                } }
        }.tint(AppTheme.foreground).presentationDragIndicator(.visible)
    }
}

struct SportsChatView: View {
    let game: SportsGame
    var sceneIsActive: Bool? = nil
    @StateObject private var chat = SportsChatStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retry = 0
    @State private var nearBottom = true
    @State private var viewportHeight: CGFloat = 300
    @State private var highlightedMessage: String?
    @State private var sendCompleted = 0
    @State private var quoteNotice: String?
    @FocusState private var composing: Bool

    private var room: String? {
        if game.league == .tennis {
            guard game.eventID.range(of: "^(espn-(atp|wta)-[0-9]{1,18}|challenger-[0-9]{1,18})$", options: .regularExpression) != nil else { return nil }
            return "TENNIS-\(game.eventID.uppercased())"
        }
        return SportsChatContract.room(league: game.league, away: game.away.abbreviation, home: game.home.abbreviation)
    }
    private var active: Bool { sceneIsActive ?? (scenePhase == .active) }
    private var observationID: String { "\(room ?? "invalid")|\(active)|\(retry)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36).background(AppTheme.foreground.opacity(0.05), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(game.away.abbreviation.isEmpty ? game.away.name : game.away.abbreviation) vs \(game.home.abbreviation.isEmpty ? game.home.name : game.home.abbreviation)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Share the moment with other fans").font(.caption2).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 4)
                Text("Public").font(.caption2.weight(.medium)).foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(0.10), lineWidth: 1) }
                    .accessibilityLabel("Public game chat")
            }.padding(.vertical, 12)
            Rectangle().fill(AppTheme.foreground.opacity(0.06)).frame(height: 1)
            if let error = chat.error { errorRow(error) { retry += 1 }.padding(.top, 10) }
            thread.overlay {
                if chat.loading, chat.messages.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to chat…").font(.subheadline.weight(.medium))
                        Text("Messages will appear here").font(.caption).foregroundStyle(AppTheme.muted)
                    }.allowsHitTesting(false)
                }
            }
            if let error = chat.actionError {
                errorRow(error) { Task { await chat.retryAction() } }
                    .accessibilityIdentifier("sports-chat-action-error").padding(.bottom, 10)
            }
            if let quoteNotice {
                Text(quoteNotice).font(.caption).foregroundStyle(AppTheme.muted).padding(.bottom, 8)
                    .accessibilityIdentifier("sports-chat-quote-notice")
            }
            composer
            Text("Be kind to fellow fans").font(.system(size: 10)).foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity).padding(.top, 8)
        }.foregroundStyle(AppTheme.foreground)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-chat")
            .task(id: observationID) { chat.listen(room: room, active: active) }
            .task(id: highlightedMessage) {
                guard highlightedMessage != nil else { return }
                do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { highlightedMessage = nil }
            }
            .onChange(of: chat.draft) { _, value in
                let limited = SportsChatContract.limitDraft(value)
                if limited != value { chat.draft = limited }
            }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.messages) { message in
                            SportsChatMessageRow(message: message, own: !message.uid.isEmpty && message.uid == chat.userID,
                                userID: chat.userID, highlighted: highlightedMessage == message.id,
                                reply: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { chat.reply = message.quote }; composing = true },
                                mention: {
                                    chat.draft = SportsChatContract.limitDraft(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines) + " @\(message.handle) ")
                                    composing = true
                                }, openQuote: { quote in
                                    composing = false
                                    guard chat.messages.contains(where: { $0.id == quote.id }) else {
                                        quoteNotice = "The original message is no longer in this conversation."
                                        return
                                    }
                                    quoteNotice = nil
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(quote.id, anchor: .center); highlightedMessage = quote.id
                                    }
                                }, react: { emoji in Task { await chat.react(messageID: message.id, emoji: emoji) } })
                                .id(message.id)
                        }
                        if !chat.loading, chat.error == nil, chat.messages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30, weight: .light)).foregroundStyle(AppTheme.muted)
                                    .padding(.bottom, 2)
                                Text("Be the first to say hello").font(.subheadline.weight(.semibold))
                                Text("Big plays are better together.").font(.caption).foregroundStyle(AppTheme.muted)
                            }.frame(maxWidth: .infinity).padding(.vertical, 52)
                        }
                        Color.clear.frame(height: 1).id("sports-chat-bottom")
                    }.padding(.vertical, 16).padding(.horizontal, 2)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: SportsChatBottom.self,
                                value: geometry.frame(in: .named("sports-chat-scroll")).maxY)
                        })
                }.coordinateSpace(name: "sports-chat-scroll").scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("sports-chat-thread")
                    .frame(maxHeight: .infinity)
                    .background(GeometryReader { geometry in
                        Color.clear.onAppear { viewportHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
                    })
                    .onPreferenceChange(SportsChatBottom.self) { bottom in nearBottom = bottom <= viewportHeight + 60 }
                    .onChange(of: sendCompleted) { _, _ in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("sports-chat-bottom", anchor: .bottom) }
                    }
                    .onChange(of: chat.messages.last?.id) { old, _ in
                        let ownNewMessage = chat.messages.last?.uid == chat.userID && chat.userID != nil
                        guard nearBottom || old == nil || ownNewMessage else { return }
                        DispatchQueue.main.async {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("sports-chat-bottom", anchor: .bottom) }
                        }
                    }
                if !nearBottom, !chat.messages.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("sports-chat-bottom", anchor: .bottom) }
                    } label: {
                        Label("Latest messages", systemImage: "arrow.down").font(.caption.weight(.semibold))
                            .padding(.horizontal, 16).frame(minHeight: 40).background(AppTheme.panel, in: Capsule())
                            .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(0.1), lineWidth: 1) }
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-chat-latest").padding(.bottom, 8)
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reply = chat.reply {
                HStack(spacing: 4) {
                    SportsChatQuotePreview(sender: "Replying to \(reply.sender)", text: reply.message)
                    Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { chat.reply = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Cancel reply")
                }.padding(.leading, 8).padding(.top, 8)
                    .accessibilityIdentifier("sports-chat-reply-preview")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 4) {
                TextField("Say something…", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4).font(.subheadline).focused($composing)
                    .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 14)
                    .tint(AppTheme.foreground).disabled(chat.sending || room == nil)
                    .accessibilityIdentifier("sports-chat-composer")
                Button { Task { await chat.send(); if chat.draft.isEmpty { sendCompleted += 1 } } } label: {
                    Group {
                        if chat.sending { ProgressView().tint(AppTheme.canvas) }
                        else { Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)) }
                    }.frame(width: 38, height: 38).foregroundStyle(AppTheme.canvas)
                        .background(AppTheme.foreground.opacity(canSend || chat.sending ? 1 : 0.2), in: Circle())
                        .frame(width: 46, height: 46).contentShape(Rectangle())
                }.buttonStyle(HapticPlainButtonStyle()).disabled(!canSend)
                    .accessibilityLabel("Send message").accessibilityIdentifier("sports-chat-send")
            }.padding(.trailing, 3).padding(.vertical, 3)
            if chat.draft.utf16.count >= 900 {
                Text("\(chat.draft.utf16.count)/1,000").font(.caption2).monospacedDigit().foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 14).padding(.bottom, 8)
            }
        }.background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(AppTheme.foreground.opacity(composing ? 0.20 : 0.10), lineWidth: 1) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: composing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: chat.reply?.id)
    }

    private var canSend: Bool { room != nil && !chat.sending && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func errorRow(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(AppTheme.muted)
            Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 40)
                .background(AppTheme.foreground.opacity(0.07), in: Capsule()).buttonStyle(HapticPlainButtonStyle()).disabled(chat.sending)
        }.padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SportsChatQuotePreview: View {
    let sender: String
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(AppTheme.foreground.opacity(0.35)).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(sender).font(.caption.weight(.semibold)).lineLimit(1)
                Text(text).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).padding(10)
            .background(AppTheme.foreground.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SportsChatMessageRow: View {
    let message: SportsChatMessage
    let own: Bool
    let userID: String?
    let highlighted: Bool
    let reply: () -> Void
    let mention: () -> Void
    let openQuote: (SportsChatReply) -> Void
    let react: (String) -> Void
    @State private var choosingReaction = false

    private var initials: String { message.sender.split(separator: " ").prefix(2).compactMap { part in part.first.map { String($0) } }.joined().uppercased() }
    private var reactionValues: [String] { SportsChatContract.reactions.filter { message.votes.values.contains($0) } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if own { Spacer(minLength: 32) }
            else {
                Text(initials).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.foreground.opacity(0.8))
                    .frame(width: 28, height: 28).background(AppTheme.foreground.opacity(0.07), in: Circle()).padding(.top, 1)
                    .accessibilityHidden(true)
            }
            VStack(alignment: own ? .trailing : .leading, spacing: 5) {
                if !own {
                    Button(action: mention) { Text(message.sender).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(AppTheme.muted) }
                        .buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Mention \(message.sender)")
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let quote = message.reply {
                        Button { openQuote(quote) } label: {
                            SportsChatQuotePreview(sender: "Reply to \(quote.sender)", text: quote.message)
                        }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("View reply to \(quote.sender)")
                            .accessibilityIdentifier("sports-chat-quote-\(message.id)")
                    }
                    Text(message.text).font(.subheadline).lineSpacing(3).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(12)
                    .background(own ? AppTheme.foreground.opacity(0.10) : AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.foreground.opacity(highlighted ? 0.50 : (own ? 0.06 : 0)), lineWidth: highlighted ? 2 : 1) }
                    .contextMenu {
                        Button("Reply", systemImage: "arrowshape.turn.up.left", action: reply).disabled(message.pending)
                        ForEach(SportsChatContract.reactions, id: \.self) { emoji in Button(emoji) { react(emoji) }.disabled(message.pending) }
                    }
                HStack(spacing: 1) {
                    if message.pending { Text("Sending…").font(.system(size: 10)).foregroundStyle(AppTheme.muted) }
                    else if let time = message.sentAt { Text(time, format: .dateTime.hour().minute()).font(.system(size: 10)).foregroundStyle(AppTheme.muted) }
                    Spacer(minLength: 8)
                    Button(action: reply) {
                        Image(systemName: "arrowshape.turn.up.left").font(.system(size: 13)).frame(width: 40, height: 32).contentShape(Rectangle())
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Reply to \(message.sender)")
                    Button { choosingReaction = true } label: {
                        Image(systemName: "face.smiling").font(.system(size: 14)).frame(width: 40, height: 32).contentShape(Rectangle())
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("React to \(message.sender)")
                        .popover(isPresented: $choosingReaction, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                            HStack(spacing: 2) {
                                ForEach(SportsChatContract.reactions, id: \.self) { emoji in
                                    Button { choosingReaction = false; react(emoji) } label: {
                                        Text(emoji).font(.system(size: 26)).frame(width: 46, height: 48)
                                            .background(AppTheme.foreground.opacity(message.votes[userID ?? ""] == emoji ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel(emoji)
                                        .accessibilityHint("React to this message")
                                        .accessibilityAddTraits(message.votes[userID ?? ""] == emoji ? .isSelected : [])
                                }
                            }.padding(8).presentationCompactAdaptation(.popover).presentationBackground(AppTheme.panel)
                        }
                }.foregroundStyle(AppTheme.muted).disabled(message.pending)
                if !reactionValues.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        reactionPills
                        ScrollView(.horizontal, showsIndicators: false) { reactionPills }
                    }
                }
            }.frame(maxWidth: 300, alignment: own ? .trailing : .leading)
            if !own { Spacer(minLength: 18) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("sports-chat-message-\(message.id)")
    }

    private var reactionPills: some View {
        HStack(spacing: 6) {
            ForEach(reactionValues, id: \.self) { emoji in
                let selected = message.votes[userID ?? ""] == emoji
                let count = message.votes.values.filter { $0 == emoji }.count
                Button { react(emoji) } label: {
                    HStack(spacing: 5) { Text(emoji).font(.system(size: 14)); Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit() }
                        .padding(.horizontal, 9).frame(minHeight: 32)
                        .background(AppTheme.foreground.opacity(selected ? 0.12 : 0.045), in: Capsule())
                        .overlay { Capsule().strokeBorder(AppTheme.foreground.opacity(selected ? 0.25 : 0.06), lineWidth: 1) }
                }.buttonStyle(HapticPlainButtonStyle()).disabled(message.pending)
                    .accessibilityLabel("\(emoji), \(count) reactions").accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("sports-chat-reaction-\(message.id)-\(emoji)")
            }
        }
    }
}

private struct SportsChatBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
