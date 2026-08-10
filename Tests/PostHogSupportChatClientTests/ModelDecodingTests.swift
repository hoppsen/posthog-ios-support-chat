@testable import PostHogSupportChatClient
import XCTest

/// Fixtures below are real responses captured from the live widget API
/// (us.i.posthog.com, 2026-08-10), not hand-written examples.
final class ModelDecodingTests: XCTestCase {
    func testDecodesSendMessageResponse() throws {
        let json = """
        {
            "ticket_id": "019fea07-2296-0000-05aa-bd7ff6bda4ea",
            "message_id": "019fea07-22c9-0000-1f2b-62e110f2f193",
            "ticket_status": "new",
            "unread_count": 0,
            "created_at": "2026-08-10T04:56:04.043678+00:00"
        }
        """
        let response = try JSONDecoder().decode(SendMessageResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.ticketId, "019fea07-2296-0000-05aa-bd7ff6bda4ea")
        XCTAssertEqual(response.ticketStatus, .new)
    }

    func testDecodesGetMessagesResponse() throws {
        let json = """
        {
            "ticket_id": "019fea07-2296-0000-05aa-bd7ff6bda4ea",
            "ticket_status": "new",
            "unread_count": 0,
            "messages": [
                {
                    "id": "019fea07-22c9-0000-1f2b-62e110f2f193",
                    "content": "[TEST] API validation",
                    "rich_content": null,
                    "author_type": "customer",
                    "author_name": "jane@example.com",
                    "created_at": "2026-08-10T04:56:04.043678+00:00"
                }
            ],
            "has_more": false
        }
        """
        let response = try JSONDecoder().decode(GetMessagesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.messages[0].authorType, .customer)
        XCTAssertNil(response.messages[0].richContent)
        XCTAssertNotNil(response.messages[0].createdAtDate)
    }

    func testDecodesTicketsResponse() throws {
        let json = """
        {
            "count": 1,
            "results": [
                {
                    "id": "019fea07-2296-0000-05aa-bd7ff6bda4ea",
                    "ticket_number": 1,
                    "status": "new",
                    "unread_count": 0,
                    "last_message": "[TEST] API validation",
                    "last_message_at": "2026-08-10T04:56:04.043678+00:00",
                    "message_count": 1,
                    "created_at": "2026-08-10T04:56:03.991276+00:00"
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(GetTicketsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.results[0].ticketNumber, 1)
        XCTAssertEqual(response.results[0].status, .new)
    }

    func testDecodesUnknownEnumValuesLeniently() throws {
        let json = """
        {
            "id": "m1",
            "content": "hi",
            "author_type": "robot_overlord",
            "created_at": "2026-08-10T04:56:04+00:00"
        }
        """
        let message = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(message.authorType, .human)
    }

    func testParsesMicrosecondTimestamps() {
        XCTAssertNotNil(ISO8601.date(from: "2026-08-10T04:56:04.043678+00:00"))
        XCTAssertNotNil(ISO8601.date(from: "2026-08-10T04:56:04.043+00:00"))
        XCTAssertNotNil(ISO8601.date(from: "2026-08-10T04:56:04+00:00"))
        XCTAssertNotNil(ISO8601.date(from: "2026-08-10T04:56:04Z"))
    }

    func testDecodesRemoteConfigConversationsBlock() throws {
        let json = """
        {
            "enabled": true,
            "widgetEnabled": false,
            "token": "test-conversations-token",
            "greetingText": "Hey, how can I help you today?",
            "color": "#1d4aff",
            "placeholderText": "Type your message...",
            "requireEmail": false,
            "collectName": false,
            "identificationFormTitle": "Before we start...",
            "identificationFormDescription": "Please provide your details so we can help you better."
        }
        """
        let config = try JSONDecoder().decode(ConversationsRemoteConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.widgetEnabled, false)
        XCTAssertFalse(config.token.isEmpty)
    }

    func testDecodesTipTapRichContent() throws {
        let json = """
        {
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [
                        {"type": "text", "text": "Hello "},
                        {"type": "text", "text": "world", "marks": [{"type": "bold"}]},
                        {"type": "text", "text": ", see "},
                        {
                            "type": "text",
                            "text": "docs",
                            "marks": [{"type": "link", "attrs": {"href": "https://posthog.com", "target": "_blank"}}]
                        }
                    ]
                }
            ]
        }
        """
        let doc = try JSONDecoder().decode(TipTapNode.self, from: Data(json.utf8))
        XCTAssertEqual(doc.type, "doc")
        let paragraph = try XCTUnwrap(doc.content?.first)
        XCTAssertEqual(paragraph.content?.count, 4)
        XCTAssertEqual(paragraph.content?[1].marks?.first?.type, "bold")
        XCTAssertEqual(paragraph.content?[3].marks?.first?.attrs?["href"], "https://posthog.com")
    }
}
