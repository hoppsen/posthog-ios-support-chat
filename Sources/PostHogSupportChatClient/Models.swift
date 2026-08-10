import Foundation

// MARK: - Remote config

/// The `conversations` block of PostHog's public remote config
/// (`GET <assetsHost>/array/<projectApiKey>/config`).
public struct ConversationsRemoteConfig: Decodable, Sendable, Equatable {
    public let enabled: Bool
    /// Public token sent as `X-Conversations-Token` on every widget API request.
    public let token: String
    public let widgetEnabled: Bool?
    public let greetingText: String?
    public let color: String?
    public let placeholderText: String?
    public let requireEmail: Bool?
    public let collectName: Bool?
    public let identificationFormTitle: String?
    public let identificationFormDescription: String?
}

// MARK: - Messages

public enum MessageAuthorType: String, Decodable, Sendable {
    case customer
    case ai = "AI"
    case human
    /// Returned by the live API for inbox replies (not in posthog-js's types).
    case support

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MessageAuthorType(rawValue: raw) ?? .human
    }
}

public struct Message: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    /// Plain-text content (always present; fallback when `richContent` is nil).
    public let content: String
    /// Rich content in TipTap JSON, rendered via `TipTapRenderer`.
    public let richContent: TipTapNode?
    public let authorType: MessageAuthorType
    public let authorName: String?
    /// Raw ISO 8601 timestamp. Kept as the server string so it can be passed
    /// back verbatim as the `after` cursor when polling incrementally.
    public let createdAt: String

    public var createdAtDate: Date? { ISO8601.date(from: createdAt) }

    enum CodingKeys: String, CodingKey {
        case id, content
        case richContent = "rich_content"
        case authorType = "author_type"
        case authorName = "author_name"
        case createdAt = "created_at"
    }
}

// MARK: - TipTap rich content

/// A node in a TipTap document tree (`rich_content`). The root node has
/// `type == "doc"`.
public struct TipTapNode: Decodable, Sendable, Equatable {
    public let type: String
    public let text: String?
    public let content: [TipTapNode]?
    public let marks: [TipTapMark]?
}

public struct TipTapMark: Decodable, Sendable, Equatable {
    public let type: String
    public let attrs: [String: String]?

    enum CodingKeys: String, CodingKey { case type, attrs }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        // attrs values can be non-string JSON; keep only string values (href, target).
        let rawAttrs = try container.decodeIfPresent([String: AnyDecodable].self, forKey: .attrs)
        attrs = rawAttrs?.compactMapValues { $0.value as? String }
    }

    init(type: String, attrs: [String: String]?) {
        self.type = type
        self.attrs = attrs
    }
}

// MARK: - Tickets

public enum TicketStatus: String, Decodable, Sendable {
    case new, open, pending, onHold = "on_hold", resolved

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TicketStatus(rawValue: raw) ?? .open
    }
}

public struct Ticket: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let ticketNumber: Int?
    public let status: TicketStatus
    public let lastMessage: String?
    public let lastMessageAt: String?
    public let messageCount: Int
    public let unreadCount: Int?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case ticketNumber = "ticket_number"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case messageCount = "message_count"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
    }
}

// MARK: - Responses

public struct SendMessageResponse: Decodable, Sendable {
    public let ticketId: String
    public let messageId: String
    public let ticketStatus: TicketStatus
    public let unreadCount: Int
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
        case messageId = "message_id"
        case ticketStatus = "ticket_status"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
    }
}

public struct GetMessagesResponse: Decodable, Sendable {
    public let ticketId: String
    public let ticketStatus: TicketStatus
    public let messages: [Message]
    public let hasMore: Bool
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
        case ticketStatus = "ticket_status"
        case messages
        case hasMore = "has_more"
        case unreadCount = "unread_count"
    }
}

public struct MarkAsReadResponse: Decodable, Sendable {
    public let success: Bool
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case unreadCount = "unread_count"
    }
}

public struct GetTicketsResponse: Decodable, Sendable {
    public let count: Int
    public let results: [Ticket]
}

// MARK: - Helpers

package enum ISO8601 {
    /// Parses server timestamps which carry microsecond precision
    /// (e.g. `2026-08-10T04:56:04.043678+00:00`).
    package static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        // ISO8601DateFormatter only accepts 3 fractional digits; trim longer fractions.
        if let dotRange = string.range(of: "."),
           let tzRange = string.range(of: "[Z+\\-]", options: .regularExpression, range: dotRange.upperBound ..< string.endIndex) {
            let fraction = String(string[dotRange.upperBound ..< tzRange.lowerBound].prefix(3))
            let trimmed = string[..<dotRange.upperBound] + fraction + string[tzRange.lowerBound...]
            if let date = fractional.date(from: String(trimmed)) { return date }
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// Minimal type-erased decodable used for TipTap mark attributes.
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}
