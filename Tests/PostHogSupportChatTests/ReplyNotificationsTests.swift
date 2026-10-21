@testable import PostHogSupportChat
import PostHogSupportChatClient
import XCTest

@MainActor
final class ReplyNotificationsTests: XCTestCase {
    private struct Context: SupportChatContextProvider {
        var distinctId: String { "test-distinct-id" }
    }

    private func makeClient() -> SupportChatClient {
        SupportChatClient(configuration: .init(projectApiKey: "phc_test"), context: Context())
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
        var received: Bool?
        client.onEvent = { event in
            if case let .notificationPermissionRequested(granted) = event {
                received = granted
            }
        }
        client.report(.notificationPermissionRequested(granted: true))
        XCTAssertEqual(received, true)
    }
}
