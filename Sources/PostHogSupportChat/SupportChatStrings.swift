import Foundation
import SwiftUI

/// App-supplied copy for the chat's user-facing strings.
///
/// Each value wins over the matching string configured in the PostHog
/// dashboard, which in turn wins over the package's bundled translations.
///
/// Dashboard strings are single-value — PostHog stores no translations for
/// them — so an app shipping in more than one language should pass its own
/// `LocalizedStringResource`s here. They resolve at display time against the
/// current locale, so they also follow an in-app language switcher.
public struct SupportChatStrings: Sendable {
    /// Headline above the conversation list and the opening bubble of a new
    /// conversation.
    public var greeting: LocalizedStringResource?
    /// Placeholder of the message input field.
    public var placeholder: LocalizedStringResource?
    /// Header of the optional email form shown before the first message.
    public var identificationTitle: LocalizedStringResource?
    /// Explanation under that header — say what the email is used for.
    public var identificationDescription: LocalizedStringResource?

    public init(greeting: LocalizedStringResource? = nil,
                placeholder: LocalizedStringResource? = nil,
                identificationTitle: LocalizedStringResource? = nil,
                identificationDescription: LocalizedStringResource? = nil) {
        self.greeting = greeting
        self.placeholder = placeholder
        self.identificationTitle = identificationTitle
        self.identificationDescription = identificationDescription
    }
}

extension SupportChatStrings {
    /// Resolves app override → dashboard value → bundled translation.
    /// Dashboard values are server data, so they are never treated as keys.
    static func text(_ override: LocalizedStringResource?,
                     dashboard: String?,
                     fallback: LocalizedStringResource) -> Text {
        if let override { return Text(override) }
        if let dashboard, !dashboard.isEmpty { return Text(verbatim: dashboard) }
        return Text(fallback)
    }

    /// Same precedence, for APIs that need a plain `String` (e.g. a
    /// `TextField` placeholder). Still resolved at render time.
    static func string(_ override: LocalizedStringResource?,
                       dashboard: String?,
                       fallback: LocalizedStringResource) -> String {
        if let override { return String(localized: override) }
        if let dashboard, !dashboard.isEmpty { return dashboard }
        return String(localized: fallback)
    }
}

extension LocalizedStringResource {
    /// Shared so the conversation-list header and the opening bubble of a new
    /// conversation cannot drift apart.
    static let packageGreeting = LocalizedStringResource("How can we help you today?",
                                                         bundle: .package,
                                                         comment: "Headline above the support conversation list, and the opening bubble of a new conversation.")
}

extension LocalizedStringResource.BundleDescription {
    /// The package's own resource bundle, for the built-in translations.
    static let package = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
}
