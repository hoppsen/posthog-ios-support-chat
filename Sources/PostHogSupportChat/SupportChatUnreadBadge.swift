import PostHogSupportChatClient
import SwiftUI
import UIKit

/// A red capsule with the number of unread support replies, for an app's
/// "Contact Support" row. Shows nothing while everything is read.
///
/// It keeps itself current: it refreshes `unreadCount` when it appears and
/// whenever the app becomes active, and the count already follows the chat
/// (opening a conversation marks it read; a reply arriving in the foreground
/// refreshes it). A device that never started a conversation makes no request.
///
/// ```swift
/// HStack {
///     Label("Contact Support", systemImage: "lifepreserver")
///     Spacer()
///     SupportChatUnreadBadge(client: supportChatClient)
/// }
/// ```
public struct SupportChatUnreadBadge: View {
    private let client: SupportChatClient

    public init(client: SupportChatClient) {
        self.client = client
    }

    public var body: some View {
        ZStack {
            // Zero-size anchor so the refresh hooks run while no capsule shows.
            Color.clear
                .frame(width: 0, height: 0)
            if client.unreadCount > 0 {
                Text(client.unreadCount, format: .number)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color.red, in: Capsule())
                    .accessibilityLabel(Text("Unread replies: \(client.unreadCount)",
                                             bundle: .module,
                                             comment: """
                                             Accessibility label of the badge on a Contact Support row. \
                                             The number is how many support replies are unread.
                                             """))
            }
        }
        .refreshingSupportChatUnreadCount(client)
    }
}

public extension View {
    /// Keeps `client.unreadCount` current while this view is on screen: it
    /// refreshes when the view appears and whenever the app becomes active. A
    /// device that never started a conversation makes no request.
    ///
    /// Use it for a tab badge. A `TabView` doesn't run a hidden tab's tasks,
    /// so attach it to the `TabView` itself and read the count on the tab:
    ///
    /// ```swift
    /// TabView {
    ///     // …
    ///     SettingsView()
    ///         .tabItem { Label("Settings", systemImage: "gearshape") }
    ///         .badge(supportChatClient.unreadCount)
    /// }
    /// .refreshingSupportChatUnreadCount(supportChatClient)
    /// ```
    ///
    /// `SupportChatUnreadBadge` does this on its own.
    func refreshingSupportChatUnreadCount(_ client: SupportChatClient) -> some View {
        task { await client.refreshUnreadCount() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await client.refreshUnreadCount() }
            }
    }
}
