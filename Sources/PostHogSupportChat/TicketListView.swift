import PostHogSupportChatClient
import SwiftUI

/// Root list of the user's conversations: resolved tickets stay browsable,
/// active ones show unread badges, and a compose button starts a fresh thread.
struct TicketListView: View {
    let client: SupportChatClient
    @Binding var path: [SupportRoute]
    var strings: SupportChatStrings = .init()

    var body: some View {
        List {
            Section {
                header
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ForEach(client.tickets) { ticket in
                    NavigationLink(value: SupportRoute.ticket(id: ticket.id, number: ticket.ticketNumber)) {
                        TicketRow(ticket: ticket)
                    }
                }
            } header: {
                Text("Previous conversations", bundle: .module,
                     comment: "Section header above the list of the user's past support conversations.")
            }
        }
        .listStyle(.plain)
        .refreshable { try? await client.refreshTickets() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            SupportChatStrings.text(strings.greeting,
                                    dashboard: client.dashboardGreeting,
                                    fallback: .packageGreeting)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Button {
                path.append(.newConversation)
            } label: {
                Text("Start a new conversation", bundle: .module, comment: "Button under a resolved conversation that begins a fresh support conversation.")
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

struct TicketRow: View {
    let ticket: Ticket

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                (ticket.lastMessage.map(Text.init)
                    ?? Text("No messages", bundle: .module,
                            comment: "Placeholder preview in the conversation list for a ticket without messages."))
                    .lineLimit(2)
                    .font(.subheadline)
                    .foregroundStyle(ticket.status == .resolved ? .secondary : .primary)

                HStack(spacing: 6) {
                    if ticket.status == .resolved {
                        Text("Resolved", bundle: .module,
                             comment: "Status label on a closed conversation in the conversation list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let timestamp = ticket.lastMessageAt.flatMap(ISO8601.date(from:)) {
                        Text(timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let unread = ticket.unreadCount, unread > 0 {
                Text("\(unread)")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(.tint, in: Circle())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }
}
