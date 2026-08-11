import Foundation
import Observation

/// High-level, observable facade over the Conversations widget API.
///
/// Owns remote config loading, session persistence, the active ticket,
/// message state, and foreground polling. UI layers observe this directly.
@MainActor
@Observable
public final class SupportChatClient {
    public enum State: Equatable {
        case idle
        case loading
        /// Support is enabled and the API is ready.
        case ready
        /// Support is disabled in the PostHog project, or config failed to load.
        case unavailable(reason: String)
    }

    /// Notable moments the host app may want to track in its own analytics.
    /// Fired on the main actor. Triggering app-side events (with full person
    /// processing) also enables PostHog workflows keyed to a real person —
    /// PostHog's internal `$conversation_ticket_created` event is personless.
    public enum Event {
        case messageSent(ticketId: String, isNewTicket: Bool)
        case identificationSubmitted(email: String)
    }

    public private(set) var state: State = .idle
    public private(set) var remoteConfig: ConversationsRemoteConfig?
    public private(set) var tickets: [Ticket] = []
    /// False until the first successful ticket fetch. Lets the UI distinguish
    /// "no tickets exist" from "tickets not loaded yet" and avoid flashing the
    /// empty new-conversation screen during startup.
    public private(set) var hasLoadedTickets = false
    public private(set) var messages: [Message] = []
    public private(set) var currentTicketId: String?
    public private(set) var currentTicketStatus: TicketStatus?
    /// Unread count of the currently open ticket (from the latest message
    /// fetch); `unreadCount` stays the app-wide sum across all tickets.
    private var currentTicketUnreadCount = 0
    public private(set) var unreadCount: Int = 0
    public private(set) var isSending = false
    public var onEvent: ((Event) -> Void)?
    /// Extra traits merged into every sent message alongside name/email.
    /// They surface on the ticket's `anonymous_traits` in the PostHog inbox —
    /// useful for stamping conversations with an entry point (e.g.
    /// `["source": "quick_action"]`) since the widget protocol has no tags.
    public var additionalTraits: [String: String] = [:]

    /// The ticket a returning user most likely wants to continue: the
    /// unresolved one with the most recent activity. `tickets` is kept
    /// sorted by last activity, so the first match wins.
    public var bestOpenTicket: Ticket? {
        tickets.first { $0.status != .resolved }
    }

    /// Set when the user dismissed the identification form without providing
    /// an email — the form is an ask, not a gate, and should not nag again
    /// for the rest of this session.
    public var identificationDeclined = false

    /// True when the config asks for an email and none has been provided or
    /// declined yet. The UI presents the identification form once per session.
    public var needsIdentification: Bool {
        remoteConfig?.requireEmail == true && store.email == nil && !identificationDeclined
    }

    public var email: String? { store.email }
    public var name: String? { store.name }

    private let configuration: SupportChatConfiguration
    private let context: SupportChatContextProvider
    private let store: SessionStore
    private var api: ConversationsAPI?
    private var pollTask: Task<Void, Never>?
    private var consecutivePollFailures = 0

    public init(configuration: SupportChatConfiguration, context: SupportChatContextProvider) {
        self.configuration = configuration
        self.context = context
        store = SessionStore(projectApiKey: configuration.projectApiKey)
    }

    // MARK: - Lifecycle

    /// Fetches remote config and restores persisted state. Safe to call
    /// repeatedly (e.g. on app foreground); reuses the loaded config.
    public func start() async {
        guard state != .ready, state != .loading else { return }
        state = .loading
        do {
            let config = try await ConversationsAPI.fetchRemoteConfig(assetsHost: configuration.host.assetsHost,
                                                                      projectApiKey: configuration.projectApiKey)
            remoteConfig = config
            api = ConversationsAPI(apiHost: configuration.host.apiHost,
                                   token: config.token,
                                   origin: configuration.origin)
            currentTicketId = store.currentTicketId
            state = .ready
        } catch {
            state = .unavailable(reason: (error as? SupportChatError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func setIdentification(email: String, name: String?) {
        store.setTraits(email: email, name: name)
        onEvent?(.identificationSubmitted(email: email))
    }

    /// Forgets the stored email/name and re-arms the identification ask —
    /// the form shows again on the next presentation (ticket access and
    /// history are untouched).
    public func clearIdentification() {
        store.clearTraits()
        identificationDeclined = false
    }

    /// Clears the active ticket so the next send starts a fresh conversation.
    /// Used when the previous ticket was resolved or the user opts to start over.
    public func prepareNewConversation() {
        currentTicketId = nil
        currentTicketStatus = nil
        currentTicketUnreadCount = 0
        messages = []
        store.setCurrentTicketId(nil)
    }

    /// Wipes local session state (Keychain entry included). Old tickets stay
    /// on PostHog but are no longer reachable from this device.
    public func reset() {
        stopPolling()
        store.reset()
        tickets = []
        hasLoadedTickets = false
        messages = []
        currentTicketId = nil
        currentTicketStatus = nil
        currentTicketUnreadCount = 0
        unreadCount = 0
    }

    // MARK: - Messaging

    @discardableResult
    public func sendMessage(_ text: String, startNewTicket: Bool = false) async throws -> SendMessageResponse {
        guard let api else { throw SupportChatError.missingRemoteConfig }
        isSending = true
        defer { isSending = false }

        let ticketId = startNewTicket ? nil : currentTicketId
        let response = try await api.sendMessage(text,
                                                 ticketId: ticketId,
                                                 widgetSessionId: store.getOrCreateWidgetSessionId(),
                                                 distinctId: context.distinctId,
                                                 email: store.email,
                                                 name: store.name,
                                                 extraTraits: additionalTraits,
                                                 sessionId: context.sessionId,
                                                 sessionReplayURL: context.sessionReplayURL)

        // The conversation may have been switched while the send was in
        // flight (back + new conversation, or another ticket opened) — do not
        // resurrect the old ticket or echo into the wrong thread.
        guard currentTicketId == ticketId else {
            onEvent?(.messageSent(ticketId: response.ticketId, isNewTicket: ticketId == nil))
            return response
        }

        let isNewTicket = currentTicketId != response.ticketId
        if isNewTicket {
            currentTicketId = response.ticketId
            store.setCurrentTicketId(response.ticketId)
        }
        currentTicketStatus = response.ticketStatus

        // Echo the sent message immediately instead of waiting for the next
        // fetch round-trip — the send response supplies its id and timestamp,
        // and later fetches dedupe by id.
        if !messages.contains(where: { $0.id == response.messageId }) {
            messages.append(Message(id: response.messageId,
                                    content: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                    richContent: nil,
                                    authorType: .customer,
                                    authorName: nil,
                                    createdAt: response.createdAt))
        }
        try? await refreshMessages()
        if isNewTicket {
            // The conversation list only updates via refreshTickets — without
            // this, a just-created ticket is missing from the list behind the
            // back button until a manual refresh.
            try? await refreshTickets()
        }
        onEvent?(.messageSent(ticketId: response.ticketId, isNewTicket: isNewTicket))
        return response
    }

    /// Loads the full message list for a ticket and makes it the active one.
    public func openTicket(_ ticketId: String) async throws {
        // Keep the cached thread when reopening the same ticket — blanking it
        // just to refetch flashes an empty conversation; refreshMessages
        // appends anything new incrementally.
        if currentTicketId != ticketId {
            messages = []
        }
        currentTicketId = ticketId
        store.setCurrentTicketId(ticketId)
        currentTicketUnreadCount = 0
        try await refreshMessages()
        await markAsRead()
    }

    public func refreshMessages() async throws {
        guard let api, let ticketId = currentTicketId else { return }
        // Incremental fetch: page forward from the newest message we have.
        // The server returns oldest-first pages of up to 50, so keep paging
        // while it reports more — otherwise a long thread would open at an
        // old message and only catch up on later polls. Bounded as a runaway
        // guard (20 pages = 1000 messages per refresh).
        for _ in 0 ..< 20 {
            let after = messages.last?.createdAt
            let response = try await api.getMessages(ticketId: ticketId,
                                                     widgetSessionId: store.getOrCreateWidgetSessionId(),
                                                     after: after)
            // Re-check after the suspension: the user may have switched
            // conversations while the request was in flight — appending then
            // would leak this ticket's messages into the new thread.
            guard currentTicketId == ticketId else { return }
            let known = Set(messages.map(\.id))
            messages.append(contentsOf: response.messages.filter { !known.contains($0.id) })
            currentTicketStatus = response.ticketStatus
            currentTicketUnreadCount = response.unreadCount
            if !response.hasMore { return }
        }
    }

    public func refreshTickets() async throws {
        guard let api else { return }
        let response = try await api.getTickets(widgetSessionId: store.getOrCreateWidgetSessionId())
        // The server returns tickets by creation date; a conversation list
        // should surface the latest activity first (verified empirically:
        // an agent reply does not move a ticket up in the server's order).
        tickets = response.results.sorted { Self.lastActivity($0) > Self.lastActivity($1) }
        unreadCount = response.results.reduce(0) { $0 + ($1.unreadCount ?? 0) }
        hasLoadedTickets = true
    }

    private static func lastActivity(_ ticket: Ticket) -> Date {
        ISO8601.date(from: ticket.lastMessageAt ?? ticket.createdAt) ?? .distantPast
    }

    public func markAsRead() async {
        guard let api, let ticketId = currentTicketId else { return }
        if let response = try? await api.markAsRead(ticketId: ticketId,
                                                    widgetSessionId: store.getOrCreateWidgetSessionId()) {
            currentTicketUnreadCount = response.unreadCount
            // Clear the cached list badge too — popping back to the list
            // does not refetch tickets.
            tickets = tickets.map { ticket in
                guard ticket.id == ticketId, ticket.unreadCount != 0 else { return ticket }
                return Ticket(id: ticket.id,
                              ticketNumber: ticket.ticketNumber,
                              status: ticket.status,
                              lastMessage: ticket.lastMessage,
                              lastMessageAt: ticket.lastMessageAt,
                              messageCount: ticket.messageCount,
                              unreadCount: 0,
                              createdAt: ticket.createdAt)
            }
            unreadCount = tickets.reduce(0) { $0 + ($1.unreadCount ?? 0) }
        }
    }

    // MARK: - Polling (mirrors the web widget: poll while visible, back off on failures)

    public func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let base = self?.configuration.pollInterval ?? 2
                // Back off exponentially (capped at 60s) on consecutive failures
                // instead of stopping — the next success resets the cadence.
                let failures = self?.consecutivePollFailures ?? 0
                let delay = min(base * pow(2, Double(failures)), 60)
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                do {
                    try await self.refreshMessages()
                    self.consecutivePollFailures = 0
                    // Polling only runs while the conversation is on screen,
                    // so anything that just arrived has been seen — without
                    // this, a reply arriving mid-view leaves the ticket's
                    // unread badge stuck until the next explicit open.
                    if self.currentTicketUnreadCount > 0 {
                        await self.markAsRead()
                    }
                } catch {
                    self.consecutivePollFailures += 1
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        consecutivePollFailures = 0
    }
}
