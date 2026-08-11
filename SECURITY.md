# Security

## Reporting a vulnerability

Please report security issues privately via [GitHub's private vulnerability reporting](https://github.com/hoppsen/posthog-ios-support-chat/security/advisories/new) rather than opening a public issue.

Include what the issue allows an attacker to do, and the smallest set of steps that reproduces it. You can expect an initial response within a week; this is a side project, not a staffed product.

## Scope

**In scope** — anything in this package: how the widget session id is generated and stored, what is written to the Keychain, what is sent to PostHog, and any way a device could read another device's conversations through this client.

**Out of scope** — the PostHog Support API itself. This package is an unofficial client for a beta, internally-versioned protocol; server-side issues belong to [PostHog](https://posthog.com/handbook/company/security) and should be reported to them directly.

## What this package handles

- **No secret keys.** Authentication uses the public conversations token from PostHog's remote config — the same token any web visitor receives. There is no private API key on the device.
- **Access control is a client-generated `widget_session_id`**, stored in the Keychain (accessible after first unlock, not synced) and sent with every request. Anyone holding that id can read the conversations created with it, so it is deliberately never logged or exposed through the public API.
- **User-provided email and name** are sent to PostHog as message traits when the user supplies them. Nothing else about the user is collected by this package; the host app supplies its own PostHog distinct id and session id via `SupportChatContextProvider`.

See `PrivacyInfo.xcprivacy` for the declared data types.
