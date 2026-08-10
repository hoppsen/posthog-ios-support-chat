import Foundation
import PostHogSupportChatClient
import SwiftUI

/// Renders TipTap `rich_content` documents into `AttributedString`.
/// Callers should fall back to the message's plain `content` when the
/// document is missing or renders to an empty string.
public enum TipTapRenderer {
    public static func render(_ message: Message) -> AttributedString {
        if let doc = message.richContent {
            let rendered = render(doc)
            if !rendered.characters.isEmpty { return rendered }
        }
        // Inbox replies arrive as markdown with rich_content null.
        if message.authorType != .customer,
           let markdown = try? AttributedString(markdown: message.content,
                                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return markdown
        }
        return AttributedString(message.content)
    }

    public static func render(_ doc: TipTapNode) -> AttributedString {
        var result = AttributedString()
        let blocks = doc.content ?? []
        for (index, block) in blocks.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            result += renderNode(block)
        }
        return result
    }

    private static func renderNode(_ node: TipTapNode) -> AttributedString {
        switch node.type {
        case "text":
            return styledText(node)
        case "hardBreak":
            return AttributedString("\n")
        case "listItem":
            var item = AttributedString("• ")
            item += renderChildren(node)
            return item
        default:
            // paragraph, heading, bulletList, orderedList, blockquote, doc, ...
            return renderChildren(node, joinBlocks: isBlockContainer(node.type))
        }
    }

    private static func renderChildren(_ node: TipTapNode, joinBlocks: Bool = false) -> AttributedString {
        var result = AttributedString()
        for (index, child) in (node.content ?? []).enumerated() {
            if joinBlocks, index > 0 { result += AttributedString("\n") }
            result += renderNode(child)
        }
        return result
    }

    private static func isBlockContainer(_ type: String) -> Bool {
        ["bulletList", "orderedList", "blockquote"].contains(type)
    }

    private static func styledText(_ node: TipTapNode) -> AttributedString {
        var text = AttributedString(node.text ?? "")
        let marks = node.marks ?? []
        for mark in marks {
            switch mark.type {
            case "underline":
                text.underlineStyle = .single
            case "strike":
                text.strikethroughStyle = .single
            case "code":
                text.font = .body.monospaced()
            case "link":
                if let href = mark.attrs?["href"], let url = URL(string: href) {
                    text.link = url
                    text.underlineStyle = .single
                }
            default:
                break
            }
        }
        if let font = emphasisFont(for: marks) {
            text.font = font
        }
        return text
    }

    /// Bold and italic combine into one font, so they are resolved together.
    private static func emphasisFont(for marks: [TipTapMark]) -> Font? {
        let isBold = marks.contains { $0.type == "bold" }
        let isItalic = marks.contains { $0.type == "italic" }
        guard isBold || isItalic else { return nil }
        var font: Font = isBold ? .body.bold() : .body
        if isItalic { font = font.italic() }
        return font
    }
}
