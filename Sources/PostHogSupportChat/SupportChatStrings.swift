import Foundation
import SwiftUI

/// App-supplied copy for the chat's user-facing strings.
///
/// Anything set here wins. Anything left `nil` falls back to the package's
/// translations, which ship in 54 languages — or, if the configuration opts
/// into `usesDashboardStrings`, to the PostHog dashboard's copy first.
///
/// Values resolve at display time against the current locale, so they follow
/// an in-app language switcher rather than freezing at the locale that was
/// active when they were constructed.
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
    /// Resolves app override → dashboard value → bundled translation. The
    /// dashboard tier is `nil` unless the configuration opts into it, so the
    /// usual chain is just override → translation.
    ///
    /// Dashboard values are server data and never treated as localization keys.
    static func text(_ override: LocalizedStringResource?,
                     dashboard: String?,
                     fallback: LocalizedStringResource) -> Text {
        if let override { return Text(override) }
        if let dashboard, !dashboard.isEmpty { return Text(verbatim: dashboard) }
        return Text(fallback)
    }

    /// Same precedence, for APIs that need a plain `String` (e.g. a
    /// `TextField` placeholder). Still resolved at render time, so it also
    /// follows a locale change.
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
