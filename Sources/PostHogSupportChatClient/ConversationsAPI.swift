import Foundation

public enum SupportChatError: Error, LocalizedError {
    /// Support/Conversations is disabled in the PostHog project settings.
    case conversationsDisabled
    /// Remote config was fetched but contained no usable conversations block.
    case missingRemoteConfig
    case httpError(statusCode: Int, body: String?)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .conversationsDisabled: "Support is disabled in the PostHog project settings."
        case .missingRemoteConfig: "PostHog remote config did not include a conversations token."
        case let .httpError(code, _): "Support request failed (HTTP \(code))."
        case .invalidResponse: "Support request returned an unreadable response."
        }
    }
}

/// Raw HTTP client for PostHog's Conversations widget API
/// (`/api/conversations/v1/widget/*`).
///
/// This speaks the same client-side protocol as the posthog-js support
/// widget: authenticated with the public conversations token from remote
/// config, access-controlled by `widget_session_id`. Note this is a beta,
/// internally-versioned protocol — see README for the endpoint map.
public struct ConversationsAPI: Sendable {
    private let apiHost: URL
    private let token: String
    private let origin: URL?
    private let session: URLSession

    public init(apiHost: URL, token: String, origin: URL? = nil, session: URLSession = .shared) {
        self.apiHost = apiHost
        self.token = token
        self.origin = origin
        self.session = session
    }

    // MARK: - Remote config

    /// Fetches the `conversations` block from the public remote config.
    /// Returns the config when Support is enabled; throws
    /// `conversationsDisabled` when the project has it turned off.
    public static func fetchRemoteConfig(assetsHost: URL,
                                         projectApiKey: String,
                                         session: URLSession = .shared) async throws -> ConversationsRemoteConfig {
        let url = assetsHost.appending(path: "/array/\(projectApiKey)/config")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SupportChatError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                             body: String(data: data, encoding: .utf8))
        }
        return try decodeRemoteConfig(from: data)
    }

    /// Decodes the remote-config envelope. `conversations` is `false` when
    /// Support is disabled and a config object when enabled.
    package static func decodeRemoteConfig(from data: Data) throws -> ConversationsRemoteConfig {
        struct RemoteConfigEnvelope: Decodable {
            let conversations: ConversationsValue?
        }
        enum ConversationsValue: Decodable {
            case disabled
            case config(ConversationsRemoteConfig)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let bool = try? container.decode(Bool.self) {
                    if bool { throw SupportChatError.missingRemoteConfig }
                    self = .disabled
                } else {
                    self = try .config(container.decode(ConversationsRemoteConfig.self))
                }
            }
        }

        let envelope = try JSONDecoder().decode(RemoteConfigEnvelope.self, from: data)
        switch envelope.conversations {
        case let .config(config) where config.enabled:
            return config
        case .config, .disabled:
            throw SupportChatError.conversationsDisabled
        case nil:
            throw SupportChatError.missingRemoteConfig
        }
    }

    // MARK: - Endpoints

    /// `POST /widget/message` — sends a message; `ticketId: nil` creates a new ticket.
    public func sendMessage(_ message: String,
                            ticketId: String?,
                            widgetSessionId: String,
                            distinctId: String,
                            email: String? = nil,
                            name: String? = nil,
                            extraTraits: [String: String] = [:],
                            sessionId: String? = nil,
                            sessionReplayURL: String? = nil) async throws -> SendMessageResponse {
        var traits: [String: Any?] = ["name": name as Any?, "email": email as Any?]
        extraTraits.forEach { traits[$0.key] = $0.value }
        var payload: [String: Any?] = ["message": message.trimmingCharacters(in: .whitespacesAndNewlines),
                                       "traits": traits,
                                       "ticket_id": ticketId,
                                       "widget_session_id": widgetSessionId,
                                       "distinct_id": distinctId]
        if let sessionId { payload["session_id"] = sessionId }
        if let sessionReplayURL {
            payload["session_context"] = ["session_replay_url": sessionReplayURL]
        }
        return try await post(path: "/api/conversations/v1/widget/message", body: payload)
    }

    /// `GET /widget/messages/{ticketId}` — pass `after` (a raw `created_at`
    /// string from the last known message) for incremental polling.
    public func getMessages(ticketId: String,
                            widgetSessionId: String,
                            after: String? = nil,
                            limit: Int = 50) async throws -> GetMessagesResponse {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit)),
                          URLQueryItem(name: "widget_session_id", value: widgetSessionId)]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        return try await get(path: "/api/conversations/v1/widget/messages/\(ticketId)", queryItems: queryItems)
    }

    /// `POST /widget/messages/{ticketId}/read`
    public func markAsRead(ticketId: String, widgetSessionId: String) async throws -> MarkAsReadResponse {
        try await post(path: "/api/conversations/v1/widget/messages/\(ticketId)/read",
                       body: ["widget_session_id": widgetSessionId])
    }

    /// `GET /widget/tickets`
    public func getTickets(widgetSessionId: String,
                           status: String? = nil,
                           limit: Int = 20,
                           offset: Int = 0) async throws -> GetTicketsResponse {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit)),
                          URLQueryItem(name: "offset", value: String(offset)),
                          URLQueryItem(name: "widget_session_id", value: widgetSessionId)]
        if let status { queryItems.append(URLQueryItem(name: "status", value: status)) }
        return try await get(path: "/api/conversations/v1/widget/tickets", queryItems: queryItems)
    }

    // MARK: - Transport

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let url = try Self.makeGetURL(apiHost: apiHost, path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Conversations-Token")
        applyOrigin(to: &request)
        return try await execute(request)
    }

    package static func makeGetURL(apiHost: URL, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: apiHost.appending(path: path),
                                             resolvingAgainstBaseURL: false) else {
            throw SupportChatError.invalidResponse
        }
        components.queryItems = queryItems
        // URLComponents leaves "+" unencoded (valid per RFC 3986), but the server
        // decodes it as a space, corrupting ISO timestamps in the `after` cursor.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw SupportChatError.invalidResponse }
        return url
    }

    private func post<T: Decodable>(path: String, body: [String: Any?], headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: apiHost.appending(path: path))
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Conversations-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyOrigin(to: &request)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let sanitized = body.mapValues { $0 ?? NSNull() }
        request.httpBody = try JSONSerialization.data(withJSONObject: sanitized)
        return try await execute(request)
    }

    /// Write endpoints reject requests without an allowlisted `Origin` when
    /// the project restricts allowed domains; URLSession never sets one.
    private func applyOrigin(to request: inout URLRequest) {
        guard let origin, let scheme = origin.scheme, let host = origin.host else { return }
        request.setValue("\(scheme)://\(host)", forHTTPHeaderField: "Origin")
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupportChatError.invalidResponse }
        guard (200 ... 201).contains(http.statusCode) else {
            throw SupportChatError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SupportChatError.invalidResponse
        }
    }
}
