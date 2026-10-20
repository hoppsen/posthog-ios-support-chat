import PostHogSupportChatClient
import SwiftUI

/// Navigation targets within the support chat stack.
enum SupportRoute: Hashable {
    case ticket(id: String, number: Int?)
    case newConversation
}

/// Drop-in support chat screen. Present it in a sheet or push it onto a
/// navigation stack:
///
/// ```swift
/// .sheet(isPresented: $showSupport) {
///     SupportChatView(client: supportChatClient)
/// }
/// ```
///
/// Navigation model: the conversation list is the root whenever tickets
/// exist, and the most recent unresolved ticket is auto-opened on top of it —
/// returning users land in their active conversation, one tap from the list.
/// With no tickets yet, the root is a fresh conversation.
public struct SupportChatView: View {
    private let client: SupportChatClient
    private let ticketId: String?
    private let startNewConversation: Bool
    private let strings: SupportChatStrings
    private let requestNotifications: (@MainActor () async -> Void)?
    @State private var path: [SupportRoute] = []
    @State private var showIdentificationForm = false
    @State private var didAutoOpen = false
    // Fallback so a failed ticket fetch (e.g. offline) still leaves the
    // spinner instead of blocking the new-conversation root forever.
    @State private var didFinishInitialLoad = false
    // Decided once after the initial load and stable for this presentation:
    // deriving the root from tickets.isEmpty live would swap a first-time
    // user's conversation for the ticket list the moment their first send
    // creates a ticket.
    @State private var rootShowsConversation = false
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - ticketId: opens this ticket on top of the conversation list, e.g.
    ///     from a tapped reply notification
    ///     (`SupportChatNotification.ticketId(from:)`). Ignored when the
    ///     ticket does not belong to this device's session; the chat then
    ///     opens as usual. Takes precedence over `startNewConversation`.
    ///     Changing it while the chat is on screen navigates to the new ticket.
    ///   - startNewConversation: opens directly into a fresh conversation
    ///     (the list stays behind the back button) instead of auto-opening
    ///     the most recent active ticket. Use for entry points whose intent
    ///     is "start a new conversation", e.g. a feedback action.
    ///   - strings: copy for this presentation, overriding the package's
    ///     translations — lets an entry point set its own tone, e.g. a
    ///     feedback action. Anything left unset falls back to those
    ///     translations, or to the dashboard's copy for a project that opts
    ///     into `usesDashboardStrings`.
    ///   - requestNotifications: enables a "Get notified when we reply" row
    ///     in conversations that have a ticket, shown while the app's
    ///     notification permission is undecided or provisional. Tapping it
    ///     calls this closure, which should request full authorization and
    ///     call `registerForRemoteNotifications()`. The package never
    ///     registers for push itself — the app owns push setup.
    public init(client: SupportChatClient,
                ticketId: String? = nil,
                startNewConversation: Bool = false,
                strings: SupportChatStrings = .init(),
                requestNotifications: (@MainActor () async -> Void)? = nil) {
        self.client = client
        self.ticketId = ticketId
        self.startNewConversation = startNewConversation
        self.strings = strings
        self.requestNotifications = requestNotifications
    }

    public var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationTitle(Text("Support", bundle: .module, comment: "Navigation title of the support chat screen. Keep it short."))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text("Close", bundle: .module,
                                                 comment: "Accessibility label of the button that closes the support chat."))
                    }
                }
                .navigationDestination(for: SupportRoute.self) { route in
                    destination(for: route)
                }
        }
        .task { await startAndAutoOpen() }
        .onChange(of: ticketId) { _, newValue in
            guard newValue != nil, didAutoOpen else { return }
            Task { await openRequestedTicketRefreshingIfNeeded() }
        }
        .sheet(isPresented: $showIdentificationForm,
               onDismiss: {
                   // Swipe-dismissal counts as declining — the ask is optional
                   // and should not re-present this session.
                   if client.needsIdentification {
                       client.identificationDeclined = true
                   }
               },
               content: {
                   IdentificationFormView(client: client, strings: strings)
                       .presentationDetents([.medium])
               })
    }

    @ViewBuilder
    private var rootContent: some View {
        switch client.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unavailable(reason):
            ContentUnavailableView {
                Label {
                    Text("Support unavailable", bundle: .module,
                         comment: "Error state title shown when support is disabled or cannot be loaded.")
                } icon: {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                }
            } description: {
                Text(reason)
            } actions: {
                Button {
                    Task { await startAndAutoOpen() }
                } label: {
                    Text("Try again", bundle: .module,
                         comment: "Retry button shown when the support chat failed to load.")
                }
            }
        case .ready:
            // Wait for the first ticket fetch before choosing a root —
            // rendering the empty new-conversation screen while tickets are
            // still loading flashes it briefly for returning users.
            if !client.hasLoadedTickets, !didFinishInitialLoad {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rootShowsConversation {
                ConversationView(client: client, strings: strings, requestNotifications: requestNotifications)
            } else {
                TicketListView(client: client, path: $path, strings: strings)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: SupportRoute) -> some View {
        switch route {
        case let .ticket(id, number):
            ConversationView(client: client, strings: strings, requestNotifications: requestNotifications)
                .task { try? await client.openTicket(id) }
                .navigationTitle(ticketTitle(number: number))
                .navigationBarTitleDisplayMode(.inline)
        case .newConversation:
            ConversationView(client: client, strings: strings, requestNotifications: requestNotifications)
                .onAppear { client.prepareNewConversation() }
                .navigationTitle(Text("New conversation", bundle: .module,
                                      comment: "Navigation title of the screen that starts a new support conversation."))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func ticketTitle(number: Int?) -> Text {
        if let number {
            Text("Ticket #\(number)", bundle: .module,
                 comment: "Navigation title of a support conversation. The number is the ticket number.")
        } else {
            Text("Support", bundle: .module, comment: "Navigation title of the support chat screen. Keep it short.")
        }
    }

    private func startAndAutoOpen() async {
        defer { didFinishInitialLoad = true }
        await client.start()
        guard client.state == .ready else { return }

        // When the client already holds tickets from a previous presentation,
        // auto-open from the cache immediately — waiting for the network
        // refresh would leave the ticket list visible for a whole round-trip.
        // A requested ticket missing from the cache waits for the refresh,
        // or the cached auto-open would land somewhere else first.
        if client.hasLoadedTickets, ticketId == nil || requestedTicket != nil {
            autoOpenIfNeeded()
        }

        try? await client.refreshTickets()
        showIdentificationForm = client.needsIdentification
        autoOpenIfNeeded()
    }

    private func autoOpenIfNeeded() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        rootShowsConversation = client.tickets.isEmpty

        if openRequestedTicket() { return }

        if startNewConversation {
            if !client.tickets.isEmpty {
                path.append(.newConversation)
            } else {
                client.prepareNewConversation()
            }
            return
        }

        // Land returning users directly in their most recent active
        // conversation; the back button reveals the list underneath. Setting
        // the path in the same turn as the ticket update keeps the list from
        // rendering on its own frame first.
        if let best = client.bestOpenTicket {
            path.append(.ticket(id: best.id, number: best.ticketNumber))
        }
    }

    /// The requested ticket, if this device's session owns it. Opening a
    /// ticket from another session would only produce a 403 and an empty
    /// thread with a composer that cannot send.
    private var requestedTicket: Ticket? {
        guard let ticketId else { return nil }
        return client.tickets.first { $0.id == ticketId }
    }

    /// Replaces the navigation stack with the requested ticket. Returns false
    /// when there is nothing to open.
    @discardableResult
    private func openRequestedTicket() -> Bool {
        guard let ticket = requestedTicket else { return false }
        path = [.ticket(id: ticket.id, number: ticket.ticketNumber)]
        return true
    }

    private func openRequestedTicketRefreshingIfNeeded() async {
        if openRequestedTicket() { return }
        // A ticket created since the last fetch is not cached yet.
        try? await client.refreshTickets()
        openRequestedTicket()
    }
}
