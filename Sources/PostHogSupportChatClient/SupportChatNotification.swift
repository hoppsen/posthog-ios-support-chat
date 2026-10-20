import Foundation

/// The payload contract between a PostHog Workflows push step and the app.
///
/// A workflow that notifies customers about inbox replies sets the push
/// step's custom data to `{"type": "support_reply", "ticket_id": "<id>"}`
/// (see the README). PostHog merges custom data keys into the top level of
/// the APNs payload, beside `aps`, so they arrive as top-level `userInfo`
/// keys — the same place FCM data keys land on iOS.
///
/// Keeping the keys here means apps route a tap with one call instead of
/// hard-coding strings that must match the workflow.
public enum SupportChatNotification {
    /// Value of the `type` key that marks a support reply.
    public static let replyType = "support_reply"
    public static let typeKey = "type"
    public static let ticketIdKey = "ticket_id"

    /// The ticket a support-reply notification is about, or nil when the
    /// notification is something else.
    ///
    /// ```swift
    /// func userNotificationCenter(_ center: UNUserNotificationCenter,
    ///                             didReceive response: UNNotificationResponse) async {
    ///     let userInfo = response.notification.request.content.userInfo
    ///     if let ticketId = SupportChatNotification.ticketId(from: userInfo) {
    ///         router.showSupport(ticketId: ticketId)
    ///     }
    /// }
    /// ```
    public static func ticketId(from userInfo: [AnyHashable: Any]) -> String? {
        guard userInfo[typeKey] as? String == replyType,
              let ticketId = userInfo[ticketIdKey] as? String,
              !ticketId.isEmpty else { return nil }
        return ticketId
    }
}
