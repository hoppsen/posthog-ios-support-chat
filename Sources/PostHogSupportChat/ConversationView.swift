import PostHogSupportChatClient
import SwiftUI

/// The message thread + composer for the active ticket.
struct ConversationView: View {
    let client: SupportChatClient
    var strings: SupportChatStrings = .init()
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private var placeholder: String {
        let bundled = LocalizedStringResource("Type your message...",
                                              bundle: .package,
                                              comment: "Placeholder of the chat message input field.")
        return SupportChatStrings.string(strings.placeholder,
                                         bundled: bundled,
                                         dashboard: client.dashboardPlaceholder)
    }

    private var greeting: Text {
        SupportChatStrings.text(strings.greeting,
                                bundled: .packageGreeting,
                                dashboard: client.dashboardGreeting)
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            if client.currentTicketStatus == .resolved {
                resolvedFooter
            } else {
                composer
            }
        }
        .onAppear { client.startPolling() }
        .onDisappear { client.stopPolling() }
    }

    /// Resolved conversations stay readable but closed for replies —
    /// a new issue gets its own thread (and clean context in the inbox).
    private var resolvedFooter: some View {
        VStack(spacing: 8) {
            Text("This conversation was resolved.", bundle: .module,
                 comment: "Notice shown instead of the message input when a support conversation is closed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                client.prepareNewConversation()
            } label: {
                Text("Start a new conversation", bundle: .module,
                     comment: "Button under a resolved conversation that begins a fresh support conversation.")
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.bar)
    }

    private static let bottomAnchorId = "conversation-bottom"

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Plain VStack: fetches are capped at 50 messages, and lazy
                // containers make scrollTo unreliable for not-yet-laid-out
                // content at the bottom of the thread.
                VStack(spacing: 12) {
                    // Greeting only belongs to a fresh conversation — an
                    // existing thread that is still loading would flash it.
                    if client.messages.isEmpty, client.currentTicketId == nil {
                        GreetingBubble(text: greeting)
                    }
                    ForEach(client.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Scroll target below the last bubble: scrolling to a
                    // message aligns its edge with the viewport and cuts off
                    // the list's bottom padding.
                    Color.clear
                        .frame(height: 4)
                        .id(Self.bottomAnchorId)
                }
                .padding([.horizontal, .top])
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: client.messages.count) { oldCount, newCount in
                guard newCount > 0 else { return }
                if oldCount == 0 {
                    // Initial load arrives after the view appears; jump to the
                    // latest message without animating through the backlog,
                    // deferred a tick so layout has settled.
                    Task { @MainActor in
                        proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                    }
                } else {
                    withAnimation { proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder,
                      text: $draft,
                      axis: .vertical)
                .lineLimit(1 ... 5)
                .textFieldStyle(.plain)
                .focused($composerFocused)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.largeTitle)
            }
            .padding(.bottom, -8)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.isSending)
        }
        .padding(.top, 12)
        .padding(.leading, 28)
        .padding([.trailing, .bottom], 16)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            do {
                try await client.sendMessage(text)
            } catch {
                // Give the text back for retry — unless the user already
                // started typing something new.
                if draft.isEmpty { draft = text }
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message

    private var isCustomer: Bool { message.authorType == .customer }

    var body: some View {
        HStack {
            if isCustomer { Spacer(minLength: 48) }
            VStack(alignment: isCustomer ? .trailing : .leading, spacing: 2) {
                if !isCustomer, let author = message.authorName {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(TipTapRenderer.render(message))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCustomer ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.systemGray5)))
                    .foregroundStyle(isCustomer ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if !isCustomer { Spacer(minLength: 48) }
        }
    }
}

struct GreetingBubble: View {
    let text: Text

    var body: some View {
        HStack {
            text
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 48)
        }
    }
}
