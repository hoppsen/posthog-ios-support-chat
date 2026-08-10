@testable import PostHogSupportChatClient
import XCTest

/// Pins the protocol behaviors documented in CLAUDE.md that go beyond plain
/// model decoding.
final class ProtocolBehaviorTests: XCTestCase {
    // The server decodes an unencoded "+" in query values as a space, which
    // corrupts ISO timestamps in the `after` cursor — the URL builder must
    // percent-encode it explicitly (URLComponents does not).
    func testGetURLPercentEncodesPlusInAfterCursor() throws {
        let url = try ConversationsAPI.makeGetURL(apiHost: URL(string: "https://us.i.posthog.com")!,
                                                  path: "/api/conversations/v1/widget/messages/abc",
                                                  queryItems: [URLQueryItem(name: "after",
                                                                            value: "2026-08-10T04:56:04.043678+00:00")])
        let query = try XCTUnwrap(url.query(percentEncoded: true))
        XCTAssertTrue(query.contains("%2B"), "plus was not percent-encoded: \(query)")
        XCTAssertFalse(query.contains("+"), "unencoded plus survived: \(query)")
    }

    func testRemoteConfigEnvelopeWithEnabledConfig() throws {
        let json = """
        {"conversations": {"enabled": true, "token": "test-conversations-token", "widgetEnabled": false}}
        """
        let config = try ConversationsAPI.decodeRemoteConfig(from: Data(json.utf8))
        XCTAssertEqual(config.token, "test-conversations-token")
    }

    func testRemoteConfigEnvelopeDisabledBoolean() {
        let json = """
        {"conversations": false}
        """
        XCTAssertThrowsError(try ConversationsAPI.decodeRemoteConfig(from: Data(json.utf8))) { error in
            guard case SupportChatError.conversationsDisabled = error else {
                return XCTFail("expected conversationsDisabled, got \(error)")
            }
        }
    }

    func testRemoteConfigEnvelopeDisabledObject() {
        let json = """
        {"conversations": {"enabled": false, "token": "test-conversations-token"}}
        """
        XCTAssertThrowsError(try ConversationsAPI.decodeRemoteConfig(from: Data(json.utf8))) { error in
            guard case SupportChatError.conversationsDisabled = error else {
                return XCTFail("expected conversationsDisabled, got \(error)")
            }
        }
    }

    func testRemoteConfigEnvelopeMissingKey() {
        let json = """
        {"surveys": []}
        """
        XCTAssertThrowsError(try ConversationsAPI.decodeRemoteConfig(from: Data(json.utf8))) { error in
            guard case SupportChatError.missingRemoteConfig = error else {
                return XCTFail("expected missingRemoteConfig, got \(error)")
            }
        }
    }

    // Unknown status values from future server versions must not fail decoding.
    func testTicketStatusDecodesUnknownValueLeniently() throws {
        let json = """
        {
            "id": "t1", "ticket_number": 1, "status": "escalated_to_hedgehog",
            "message_count": 1, "created_at": "2026-08-10T04:56:04+00:00"
        }
        """
        let ticket = try JSONDecoder().decode(Ticket.self, from: Data(json.utf8))
        XCTAssertEqual(ticket.status, .open)
    }

    // The fraction-trimming fallback must survive timestamps whose fraction
    // exceeds what the first-attempt parser accepts.
    func testISO8601FallbackTrimsLongFractions() {
        XCTAssertNotNil(ISO8601.date(from: "2026-08-10T04:56:04.0436789012+00:00"))
        XCTAssertNotNil(ISO8601.date(from: "2026-08-10T04:56:04.0436789012Z"))
    }
}
