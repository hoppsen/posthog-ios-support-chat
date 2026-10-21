import PostHogSupportChatClient
import SwiftUI
import UIKit

public extension SupportChatClient {
    /// Tint for the chat presented by `presentInOverlay`. A new window starts
    /// a fresh environment, so the app's tint does not reach it on its own.
    /// Nil keeps the system tint.
    var overlayTint: Color? {
        get { SupportChatUIState.of(self).overlayTint }
        set { SupportChatUIState.of(self).overlayTint = newValue }
    }

    /// Presents `SupportChatView` in its own window above everything —
    /// including full-screen covers such as an onboarding flow, which a
    /// regular SwiftUI sheet cannot cover. Made for entry points that must
    /// always reach the chat: a feedback quick action, a tapped reply.
    ///
    /// One overlay at a time: while one is up, further calls leave it in
    /// place. Reply notifications follow `SupportChatConfiguration`.
    ///
    /// - Parameter source: stamped on sent messages as the `source` trait,
    ///   e.g. `"quick_action"`, so the inbox shows the entry point.
    func presentInOverlay(ticketId: String? = nil,
                          startNewConversation: Bool = false,
                          strings: SupportChatStrings = .init(),
                          source: String) {
        let state = SupportChatUIState.of(self)
        guard state.overlayWindow == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }

        additionalTraits["source"] = source

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .clear
        window.makeKeyAndVisible()

        let chat = SupportChatView(client: self,
                                   ticketId: ticketId,
                                   startNewConversation: startNewConversation,
                                   strings: strings)
            .tint(state.overlayTint)
        let host = DismissReportingHostingController(rootView: chat)
        host.onDismiss = { [weak self] in self?.dismissOverlay() }
        state.overlayWindow = window

        // Defer one runloop: presenting synchronously during scene activation can be
        // dropped (e.g. while a system alert holds key right after launch).
        DispatchQueue.main.async { [weak self] in
            window.rootViewController?.present(host, animated: true)
            // Self-heal: if the presentation was dropped anyway, tear the window down
            // so the next attempt is not swallowed by the one-overlay guard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if host.presentingViewController == nil {
                    self?.dismissOverlay()
                }
            }
        }
    }

    /// Opens the conversation a tapped reply notification is about, above
    /// whatever the app is showing, and reports
    /// `Event.replyNotificationOpened`. Get the id from
    /// `SupportChatNotification.ticketId(from:)`. A tap while the chat is
    /// already up leaves it in place; its ticket list shows the new reply.
    func openReplyNotification(ticketId: String) {
        report(.replyNotificationOpened(ticketId: ticketId))
        presentInOverlay(ticketId: ticketId, source: "reply_notification")
    }

    private func dismissOverlay() {
        let state = SupportChatUIState.of(self)
        state.overlayWindow?.isHidden = true
        state.overlayWindow = nil
    }
}

/// Hosting controller that reports its dismissal (close button or swipe) so
/// the overlay window can be torn down with it.
private final class DismissReportingHostingController<Content: View>: UIHostingController<Content> {
    var onDismiss: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onDismiss?()
        }
    }
}
