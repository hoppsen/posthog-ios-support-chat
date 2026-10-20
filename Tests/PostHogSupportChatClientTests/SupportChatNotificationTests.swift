import PostHogSupportChatClient
import XCTest

/// Pins the push payload contract. The shape mirrors what PostHog's APNs
/// sender builds (`buildApnsPayload` in posthog's push-notification service):
/// custom data spread at the top level beside `aps`, plus the `posthog`
/// correlation entry the SDK reads for open tracking.
final class SupportChatNotificationTests: XCTestCase {
    private func apnsUserInfo(data: [String: Any]) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = ["aps": ["alert": ["title": "New reply from support", "body": "Thanks for reaching out!"],
                                                    "sound": "default",
                                                    "thread-id": "support-01a1083c-aacf-0000-dfc2-f5439a19dc8a"],
                                            "posthog": #"{"invocation_id":"inv","hog_flow_id":"flow"}"#]
        for (key, value) in data {
            userInfo[key] = value
        }
        return userInfo
    }

    func testSupportReplyYieldsTicketId() {
        let userInfo = apnsUserInfo(data: ["type": "support_reply",
                                           "ticket_id": "01a1083c-aacf-0000-dfc2-f5439a19dc8a"])
        XCTAssertEqual(SupportChatNotification.ticketId(from: userInfo), "01a1083c-aacf-0000-dfc2-f5439a19dc8a")
    }

    func testOtherNotificationTypesAreIgnored() {
        let userInfo = apnsUserInfo(data: ["type": "promo", "ticket_id": "01a1083c-aacf-0000-dfc2-f5439a19dc8a"])
        XCTAssertNil(SupportChatNotification.ticketId(from: userInfo))
    }

    func testMissingOrEmptyTicketIdIsIgnored() {
        XCTAssertNil(SupportChatNotification.ticketId(from: apnsUserInfo(data: ["type": "support_reply"])))
        XCTAssertNil(SupportChatNotification.ticketId(from: apnsUserInfo(data: ["type": "support_reply", "ticket_id": ""])))
    }

    func testNotificationWithoutCustomDataIsIgnored() {
        XCTAssertNil(SupportChatNotification.ticketId(from: apnsUserInfo(data: [:])))
    }
}
