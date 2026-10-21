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
}
