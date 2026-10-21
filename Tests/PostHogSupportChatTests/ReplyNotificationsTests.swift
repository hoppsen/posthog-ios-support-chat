@testable import PostHogSupportChat
import PostHogSupportChatClient
import XCTest

@MainActor
final class ReplyNotificationsTests: XCTestCase {
    private struct Context: SupportChatContextProvider {
        var distinctId: String { "test-distinct-id" }
    }

    private func makeClient(offersReplyNotifications: Bool = false) -> SupportChatClient {
        SupportChatClient(configuration: .init(projectApiKey: "phc_test", offersReplyNotifications: offersReplyNotifications),
                          context: Context())
    }

    func testReplyGetsABannerWhileNoConversationIsOnScreen() {
        let client = makeClient()
        XCTAssertNil(client.visibleTicketId)
        XCTAssertEqual(client.presentationOptions(forReplyTo: "01a1083c-aacf-0000-dfc2-f5439a19dc8a"), [.banner, .list, .sound])
    }

    func testOnlyTheBuiltInModeEqualsBuiltIn() {
        XCTAssertEqual(ReplyNotificationsMode.builtIn, .builtIn)
        XCTAssertNotEqual(ReplyNotificationsMode.custom {}, .builtIn)
        XCTAssertNotEqual(ReplyNotificationsMode.custom {}, .off)
    }

    func testReportForwardsToOnEvent() {
        let client = makeClient()
        var received: (granted: Bool, source: NotificationPermissionSource)?
        client.onEvent = { event in
            if case let .notificationPermissionRequested(granted, source) = event {
                received = (granted, source)
            }
        }
        client.report(.notificationPermissionRequested(granted: true, source: .settings))
        XCTAssertEqual(received?.granted, true)
        XCTAssertEqual(received?.source, .settings)
    }

    func testConfigurationDecidesUnlessThePresentationOverrides() {
        XCTAssertFalse(makeClient().offersReplyNotifications)
        XCTAssertTrue(makeClient(offersReplyNotifications: true).offersReplyNotifications)
    }

    func testEachClientHasOnePermissionModel() {
        let client = makeClient()
        XCTAssertTrue(client.notificationPermission === client.notificationPermission)
        XCTAssertFalse(client.notificationPermission === makeClient().notificationPermission)
    }

    func testPermissionIsUnknownUntilRead() {
        let permission = makeClient().notificationPermission
        XCTAssertNil(permission.status)
        XCTAssertFalse(permission.canRequest)
        XCTAssertFalse(permission.allowsDelivery)
        XCTAssertEqual(permission.analyticsValue, "unknown")
    }

    func testOverlayTintIsPerClient() {
        let client = makeClient()
        client.overlayTint = .red
        XCTAssertEqual(client.overlayTint, .red)
        XCTAssertNil(makeClient().overlayTint)
    }

    // MARK: - Unread badge

    func testRefreshUnreadCountWithoutSessionMakesNoRequest() async {
        // A fresh project key has no Keychain session: refreshUnreadCount must
        // not even load the remote config.
        let client = SupportChatClient(configuration: .init(projectApiKey: "phc_no_session_\(UUID().uuidString)"),
                                       context: Context())
        await client.refreshUnreadCount()
        XCTAssertEqual(client.state, .idle)
        XCTAssertEqual(client.unreadCount, 0)
    }

    // MARK: - Reusing an open chat

    func testTappedReplyNavigatesAChatThatIsAlreadyPresented() {
        let client = makeClient()
        let routing = SupportChatUIState.of(client).routing
        routing.chatAppeared()

        client.openReplyNotification(ticketId: "ticket-a")

        XCTAssertEqual(routing.request?.ticketId, "ticket-a")
        XCTAssertNil(SupportChatUIState.of(client).overlayWindow, "no second chat on top")
    }

    func testTappedReplyWithoutAPresentedChatDoesNotRoute() {
        let client = makeClient()
        client.openReplyNotification(ticketId: "ticket-a")
        XCTAssertNil(SupportChatUIState.of(client).routing.request)
    }

    func testRepeatedRequestsForTheSameTicketAreDistinct() {
        let routing = SupportChatUIState.of(makeClient()).routing
        routing.open(ticketId: "ticket-a")
        let first = routing.request
        routing.open(ticketId: "ticket-a")
        XCTAssertNotEqual(first, routing.request)
    }

    func testPresentedChatCountNeverGoesNegative() {
        let routing = SupportChatUIState.of(makeClient()).routing
        routing.chatDisappeared()
        XCTAssertFalse(routing.isChatPresented)
        routing.chatAppeared()
        routing.chatAppeared()
        routing.chatDisappeared()
        XCTAssertTrue(routing.isChatPresented)
    }

    // MARK: - Conversation list preview

    func testPreviewResolvesMarkdownEscapesLinksAndEmphasis() {
        XCTAssertEqual(TipTapRenderer.plainPreview(#"nichts\. bei dir?"#), "nichts. bei dir?")
        XCTAssertEqual(TipTapRenderer.plainPreview(#"Expires on \[date\]"#), "Expires on [date]")
        XCTAssertEqual(TipTapRenderer.plainPreview("Mail [marcel@example\\.com](mailto:marcel@example.com) **now**"),
                       "Mail marcel@example.com now")
    }

    func testPreviewKeepsPlainTextAndLineBreaks() {
        XCTAssertEqual(TipTapRenderer.plainPreview("How do I cancel?"), "How do I cancel?")
        XCTAssertEqual(TipTapRenderer.plainPreview("Hi,\nthanks"), "Hi,\nthanks")
    }
}
