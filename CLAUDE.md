# posthog-ios-support-chat — Development Notes

Context for anyone (human or AI) working on this package. It complements the
README: the README says how to use the package; this file records how the
underlying protocol behaves and why the package is shaped the way it is.

## What this package is

A native iOS client for [PostHog Support](https://posthog.com/docs/support/widget)
(Conversations), speaking the same client-side widget protocol as posthog-js
(`/api/conversations/v1/widget/*`). PostHog Support is in beta and official
mobile SDK support is tracked upstream ([PostHog/posthog#56771](https://github.com/PostHog/posthog/issues/56771));
this package exists to bridge that gap for apps that want in-app support chat
today. When official mobile support ships, the intent is to swap this
package's transport layer for the official one while keeping the UI, or to
retire the package entirely if the official implementation covers everything.

## Architecture

Two targets, deliberately separated:

- `PostHogSupportChatClient` — transport only. Remote config fetch, the widget
  API endpoints, Keychain-backed session persistence, polling. This is the
  disposable layer: it speaks a beta protocol and is expected to be replaced.
- `PostHogSupportChat` — SwiftUI UI (conversation list, thread, identification
  form, TipTap/markdown rendering). This is the durable layer.

The package has zero dependencies. App-side PostHog SDK state (distinct id,
session id, replay URL) comes in through the `SupportChatContextProvider`
protocol, so the package never pins a posthog-ios version.

## Protocol notes (verified against the live API, August 2026)

All endpoints live under the ingestion host (`us.i.posthog.com` /
`eu.i.posthog.com`) and authenticate with the public conversations token from
remote config (`GET <assets host>/array/<project api key>/config` →
`conversations.token`), sent as `X-Conversations-Token`. The `conversations`
key is `false` when Support is disabled and a config object when enabled.

Access control is the `widget_session_id`: a client-generated UUID sent with
every request. Only the session that created a ticket can read it (verified:
foreign session ids receive 403). This package stores it in the Keychain so
ticket history survives app reinstalls on the same device.

Findings that go beyond the TypeScript types in posthog-js:

- `GET .../messages/{id}?after=<ISO timestamp>`: the `+` in timezone offsets
  must be percent-encoded. `URLComponents` leaves `+` unencoded (valid per
  RFC 3986), and the server decodes it as a space, which breaks the cursor.
- `author_type` can be `support` (inbox replies), in addition to the
  documented `customer` / `AI` / `human`. Decoding is lenient so future
  values degrade gracefully.
- Inbox replies arrive with `rich_content: null` and markdown in `content`,
  so the renderer falls back to markdown parsing for non-customer messages.
  Widget-originated rich text uses TipTap JSON in `rich_content`.
- Tickets carry a `ticket_number` (used in navigation titles).
- Message pagination is forward-only: the first page returns the *oldest*
  messages (up to `limit`, max observed 50) with `has_more`, and clients page
  forward by passing the last message's raw `created_at` as `after`. There is
  no `before` cursor. `refreshMessages` therefore drains `has_more` in a loop
  so long threads open at the latest message instead of catching up over
  subsequent polls.
- The widget API rate-limits bursts (HTTP 429 with a `throttled_error` JSON
  body naming the retry delay). Normal chat usage never approaches it, but
  batch operations should pace themselves; the polling backoff absorbs 429s.
- The domain allowlist in Support settings affects native clients unevenly:
  with a non-empty list, write endpoints (e.g. `POST .../message`) reject
  requests whose `Origin` header is missing or not allowlisted, while read
  endpoints accept requests without one. URLSession never sets `Origin`, so
  native sends break the moment a domain is added in the dashboard. The
  `SupportChatConfiguration.origin` option sends an explicit `Origin` with
  every request for projects that restrict domains; leave it nil when the
  project's domain list is empty (empty = allow all).

## Why there is no restore / deep-link support (for now)

The web widget offers email-based ticket recovery (`POST .../restore/request`
sends an email containing a one-time `ph_conv_restore` token;
`POST .../restore` redeems it and re-links tickets to a new session id). We
implemented and verified the full flow end-to-end, then removed it from the
package. The findings, for whenever this is revisited:

- Both restore endpoints require an `Origin` header matching an allowlisted
  domain in the project's Support settings (browsers send it automatically;
  URLSession must set it explicitly). Without it: 403.
- Migration is keyed on email: only tickets whose messages carried a matching
  `traits.email` are re-linked. Restore is therefore only useful when an
  email is collected before the first message (`requireEmail`).
- Restore tokens are strictly one-time (`token_already_used` on replay) and
  expire.
- The restore email routes through an email-click-tracking redirect before
  reaching the configured `request_url`. iOS Universal Links do not fire
  through redirects, so tapping the email opens the browser rather than the
  app; an app currently needs a landing page with its own open-in-app
  affordance to complete the loop.

On iOS the Keychain already preserves ticket access across reinstalls on the
same device, which covers the common case for anonymous users. The remaining
case (moving to a new device) is rare enough that we prefer to wait for
first-class mobile support upstream rather than ship the browser-oriented
flow. The endpoint shapes and requirements above are the hard-won part —
start from them if you re-add it.

## Localization

UI strings live in `Sources/PostHogSupportChat/Resources/Localizable.xcstrings`
(54 languages). `bundle: .module` is required on every `Text`/`String(localized:)`.
Translation workflow: `bundle exec fastlane translate_batch` (see README).
These translations are what the chat renders by default. Host apps can pass
their own copy through `SupportChatStrings`, which wins; the dashboard's
greeting, placeholder, and identification texts participate only when a
project sets `usesDashboardStrings` — they are single-value, so they are off
by default and would otherwise defeat these translations entirely.

## Testing

`Tests/` pins the protocol with fixtures captured from live API responses
(not hand-written). If a test breaks after a PostHog change, update the
fixture from a real response and adjust the models — the fixtures are the
source of truth for what the server actually returns.
