import Observation
import PostHogSupportChatClient
import SwiftUI
import UIKit
import UserNotifications

/// Reply-notification plumbing that does not depend on the app: asking for
/// permission, registering with APNs, and deciding whether a reply that
/// arrives in the foreground deserves a banner.
///
/// What stays in the app: being the `UNUserNotificationCenterDelegate` (one
/// delegate per app, shared with its other notifications and with
/// posthog-ios) and the look of any Settings row. posthog-ios (3.69.0+)
/// uploads the device token on its own once the package registers.
public extension SupportChatClient {
    /// The app's notification permission, shared by the chat's "Get notified
    /// when we reply" row and any Settings row, so both always show the same
    /// state. See `SupportChatNotificationPermission`.
    var notificationPermission: SupportChatNotificationPermission {
        SupportChatUIState.of(self).permission
    }

    /// Asks for full notification permission (alerts, sounds, badges),
    /// registers with APNs when granted, and reports
    /// `Event.notificationPermissionRequested`. Shows the system dialog while
    /// the permission is undecided or provisional; otherwise returns the
    /// current answer without asking.
    @discardableResult
    func requestNotificationPermission(source: NotificationPermissionSource) async -> Bool {
        await notificationPermission.request(source: source)
    }

    /// Registers with APNs again when permission was already granted. Call it
    /// at launch: tokens can change, and registering is cheap and idempotent.
    func refreshPushRegistration() async {
        await notificationPermission.refresh()
        guard notificationPermission.allowsDelivery else { return }
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

/// The app's notification permission as the support chat sees it. Observable,
/// so a Settings row built on it updates on its own: after the chat asks
/// (quietly on a new ticket, or through "Turn on"), after a system dialog, and
/// when the app returns from the system settings.
///
/// ```swift
/// struct NotificationsRow: View {
///     let permission = supportChatClient.notificationPermission
///
///     var body: some View {
///         Button {
///             Task { await permission.requestOrOpenSettings(source: .settings) }
///         } label: {
///             LabeledContent("Notifications", value: permission.allowsDelivery ? "On" : "Off")
///         }
///         .task { await permission.refresh() }
///     }
/// }
/// ```
@MainActor
@Observable
public final class SupportChatNotificationPermission {
    /// Nil until first read; call `refresh()` from a view's `.task`.
    public private(set) var status: UNAuthorizationStatus?

    /// Whether iOS will still show its permission dialog: undecided, or
    /// provisional (quiet delivery, which the dialog upgrades). Once decided,
    /// only the system settings can change the permission.
    public var canRequest: Bool {
        status == .notDetermined || status == .provisional
    }

    /// Whether notifications reach the user at all, banners or quietly.
    public var allowsDelivery: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    /// The status as a stable snake_case string for analytics, e.g.
    /// `not_determined`; `unknown` before the first read.
    public var analyticsValue: String {
        switch status {
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        default: "unknown"
        }
    }

    @ObservationIgnored private weak var client: SupportChatClient?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(client: SupportChatClient) {
        self.client = client
        // Returning from the system settings, or from a permission dialog.
        activationObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                                    object: nil,
                                                                    queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    /// Reads the current permission.
    public func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for full permission (alerts, sounds, badges), registers with APNs
    /// when granted, and reports `Event.notificationPermissionRequested`.
    @discardableResult
    public func request(source: NotificationPermissionSource) async -> Bool {
        let granted = await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        client?.report(.notificationPermissionRequested(granted: granted, source: source))
        await refresh()
        return granted
    }

    /// What a Settings row does on tap: asks while iOS can still show its
    /// dialog, otherwise opens the app's notification settings — the only way
    /// back after a "Don't Allow".
    public func requestOrOpenSettings(source: NotificationPermissionSource) async {
        if status == nil {
            await refresh()
        }
        if canRequest {
            await request(source: source)
        } else {
            openSystemSettings()
        }
    }

    /// Opens this app's notification settings within system settings.
    public func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Quietly requests provisional permission, so a reply lands in
    /// Notification Center even if the user never taps "Turn on". Shows no
    /// dialog and does nothing once the user has decided. The chat calls this
    /// when a message creates a ticket.
    func requestProvisional() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        if await (try? center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])) == true {
            UIApplication.shared.registerForRemoteNotifications()
        }
        await refresh()
    }
}

/// UI-layer state attached to a client: the permission model and the overlay
/// window. Extensions cannot add stored properties, so it lives here, keyed by
/// client. Apps hold one client for their lifetime.
@MainActor
final class SupportChatUIState {
    private static var states: [ObjectIdentifier: SupportChatUIState] = [:]

    static func of(_ client: SupportChatClient) -> SupportChatUIState {
        let key = ObjectIdentifier(client)
        if let state = states[key] {
            return state
        }
        let state = SupportChatUIState(client: client)
        states[key] = state
        return state
    }

    let permission: SupportChatNotificationPermission
    var overlayWindow: UIWindow?
    var overlayTint: Color?

    private init(client: SupportChatClient) {
        permission = SupportChatNotificationPermission(client: client)
    }
}
