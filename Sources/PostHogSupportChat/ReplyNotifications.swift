import PostHogSupportChatClient
import UIKit
import UserNotifications

/// Reply-notification plumbing that does not depend on the app: asking for
/// permission, registering with APNs, and deciding whether a reply that
/// arrives in the foreground deserves a banner.
///
/// What stays in the app: being the `UNUserNotificationCenterDelegate` (one
/// delegate per app, shared with its other notifications and with
/// posthog-ios), deciding how a tapped reply opens the chat, and uploading
/// the device token — posthog-ios (3.69.0+) does that on its own once the
/// app registers.
public extension SupportChatClient {
    /// Asks for full notification permission (alerts, sounds, badges) and
    /// registers with APNs when granted. Shows the system dialog while the
    /// permission is undecided or provisional; otherwise returns the current
    /// answer without asking.
    ///
    /// The chat's "Get notified when we reply" row calls this and reports
    /// `Event.notificationPermissionRequested`; call it yourself from other
    /// entry points, such as a Settings row.
    @discardableResult
    func requestNotificationPermission() async -> Bool {
        let granted = await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    /// Quietly requests provisional permission, so a reply lands in
    /// Notification Center even if the user never taps "Turn on". Shows no
    /// dialog and does nothing once the user has decided. The chat calls this
    /// when a message creates a ticket.
    func requestProvisionalNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined,
              await (try? center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])) == true else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Registers with APNs again when permission was already granted. Call it
    /// at launch: tokens can change, and registering is cheap and idempotent.
    func refreshPushRegistration() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Foreground presentation for a support reply: nothing for the
    /// conversation already on screen (polling shows the reply in the
    /// thread), a banner for any other, and a ticket refresh so the
    /// conversation list shows the new unread badge.
    ///
    /// Takes the ticket id rather than the notification, so a `nonisolated`
    /// delegate method only sends a `String` to the main actor:
    ///
    /// ```swift
    /// nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
    ///                                         willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    ///     guard let ticketId = SupportChatNotification.ticketId(from: notification.request.content.userInfo) else {
    ///         return [.banner, .list, .sound]
    ///     }
    ///     return await supportChatClient.presentationOptions(forReplyTo: ticketId)
    /// }
    /// ```
    func presentationOptions(forReplyTo ticketId: String) -> UNNotificationPresentationOptions {
        if visibleTicketId == ticketId {
            return []
        }
        Task { try? await refreshTickets() }
        return [.banner, .list, .sound]
    }
}
