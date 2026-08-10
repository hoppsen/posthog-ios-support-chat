import Foundation
import Security

/// Persists the widget session id (the access-control key for all tickets)
/// and user-provided traits in the Keychain, keyed by project API key.
///
/// Keychain deliberately: entries survive app deletion on iOS, so a
/// reinstalling user keeps access to their ticket history even though their
/// PostHog distinct id rotates.
public struct SessionStore: Sendable {
    struct State: Codable {
        var widgetSessionId: String
        var email: String?
        var name: String?
        var currentTicketId: String?
    }

    private let service = "com.hoppsen.posthog-support-chat"
    private let account: String

    public init(projectApiKey: String) {
        account = projectApiKey
    }

    /// Returns the persistent widget session id, generating one on first use.
    public func getOrCreateWidgetSessionId() -> String {
        if let state = read() { return state.widgetSessionId }
        let id = UUID().uuidString.lowercased()
        write(State(widgetSessionId: id))
        return id
    }

    public var email: String? { read()?.email }
    public var name: String? { read()?.name }
    public var currentTicketId: String? { read()?.currentTicketId }

    public func setTraits(email: String?, name: String?) {
        var state = read() ?? State(widgetSessionId: UUID().uuidString.lowercased())
        if let email { state.email = email }
        if let name { state.name = name }
        write(state)
    }

    public func setCurrentTicketId(_ id: String?) {
        var state = read() ?? State(widgetSessionId: UUID().uuidString.lowercased())
        state.currentTicketId = id
        write(state)
    }

    public func reset() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain plumbing

    private func read() -> State? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func write(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         // Available after first unlock so background refreshes work;
                                         // NOT ThisDeviceOnly so the entry can migrate via encrypted backup.
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
