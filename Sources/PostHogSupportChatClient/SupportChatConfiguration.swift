import Foundation

/// Static configuration for the support chat client.
public struct SupportChatConfiguration: Sendable {
    public enum Host: Sendable {
        case us
        case eu
        case custom(api: URL, assets: URL)

        var apiHost: URL {
            switch self {
            case .us: URL(string: "https://us.i.posthog.com")!
            case .eu: URL(string: "https://eu.i.posthog.com")!
            case let .custom(api, _): api
            }
        }

        var assetsHost: URL {
            switch self {
            case .us: URL(string: "https://us-assets.i.posthog.com")!
            case .eu: URL(string: "https://eu-assets.i.posthog.com")!
            case let .custom(_, assets): assets
            }
        }
    }

    /// The PostHog project API key (`phc_...`), same one used by posthog-ios.
    public let projectApiKey: String
    public let host: Host
    /// Interval for polling new messages while a conversation is on screen.
    public let pollInterval: TimeInterval
    /// Origin to send with every request (e.g. `https://example.com`).
    /// Required when the PostHog project's Support settings restrict allowed
    /// domains: write endpoints reject requests whose `Origin` is missing or
    /// not allowlisted. Browsers set this header automatically; URLSession
    /// does not. Leave nil when the project's domain list is empty.
    public let origin: URL?

    public init(projectApiKey: String,
                host: Host = .us,
                pollInterval: TimeInterval = 2,
                origin: URL? = nil) {
        self.projectApiKey = projectApiKey
        self.host = host
        self.pollInterval = max(1, pollInterval)
        self.origin = origin
    }
}

/// Bridges app-side PostHog SDK state into the chat client without this
/// package depending on posthog-ios. Implement it with `PostHogSDK.shared`.
public protocol SupportChatContextProvider: Sendable {
    /// Current PostHog distinct id; links tickets to the person profile.
    var distinctId: String { get }
    /// Current PostHog session id, if available (links tickets to sessions/replays).
    var sessionId: String? { get }
    /// Session replay URL, if mobile session replay is active.
    var sessionReplayURL: String? { get }
}

public extension SupportChatContextProvider {
    var sessionId: String? { nil }
    var sessionReplayURL: String? { nil }
}
