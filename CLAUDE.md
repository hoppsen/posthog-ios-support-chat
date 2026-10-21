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

## Push notifications for replies (verified October 2026)

Push is sent by PostHog Workflows (see the README recipe). The package
covers everything on the device that does not depend on the app: the
permission row, provisional permission on a new ticket, APNs registration,
foreground banners (`presentationOptions(forReplyTo:)`), badge clearing, the
permission state behind an app's Settings row (`SupportChatNotificationPermission`,
observable, shared with the chat row) and opening a tapped reply in an
`.alert`-level overlay window (`SupportChatOverlay.swift`). All of it is in the
UI target, since none of it is transport; per-client UI state lives in
`SupportChatUIState` because extensions cannot add stored properties. The app
keeps the notification delegate — one per app, shared with its other
notifications and posthog-ios — the analytics mapping, and its rows' look.
Findings:

- `$conversation_message_sent` (a team reply) is a regular event, but it
  belongs to the **replying PostHog user** (its `distinct_id` is theirs).
- A push step reads device tokens from the person the workflow run belongs
  to (`globals.person`); its required "Distinct ID" input is only used in
  log messages. So a push in a workflow triggered by a reply searches the
  team member's devices — while logging the customer's id in
  `No active APNS device token found for distinct_id: …`. A run cannot
  switch person, hence two workflows: A (reply → "Get conversation ticket"
  → capture `support:reply_received` with the ticket's `distinct_id`) and
  B (that event → push). `postHogCapture` events do trigger workflows; loop
  protection only stops chains after 10 hops. The hand-off costs one
  ingestion round trip (~100 s observed). Reported upstream as
  [PostHog/posthog#120326](https://github.com/PostHog/posthog/issues/120326);
  once the push step honors its Distinct ID, this collapses back into one
  workflow with no change to the package or apps.
- "Get conversation ticket" (`template-posthog-get-ticket`) returns the
  customer's `distinct_id`: the id sent with the message that created the
  ticket (`SupportChatContextProvider.distinctId`).
- `message_content` is the reply's markdown, truncated to 1,000 characters.
  The workflow's Liquid templating rejects a backslash in any string literal,
  so markdown escapes (`\.`) cannot be stripped in the push body.
- posthog-ios registers device tokens on its own (3.69.0+ only; verified
  in a SwiftUI app, though the token can arrive a launch later). A device
  without a token logs `No active APNS device token found for distinct_id`
  — nothing is sent and the run does not fail. Tokens are stored as person
  properties (`$device_push_subscription_<bundle id>:<hash>`, encrypted),
  so after an `identify()` merge they should stay reachable through the
  pre-identify id stored on a ticket (inferred from PostHog's code, untested).
- Tokens carry no APNs environment. With both a production and a sandbox
  channel selected, every token is sent to both; the wrong environment
  answers BadDeviceToken, which PostHog logs as an `invalid_token` error
  (not pruned). Live workflows should select the production channel only.
- PostHog spreads the push step's custom `data` into the top level of the
  APNs payload beside `aps` (and FCM data lands at the top level of
  `userInfo` too). The `posthog` key is reserved for open-tracking
  correlation. `SupportChatNotification` pins the `type` / `ticket_id` keys.
- The app's `UNUserNotificationCenterDelegate` methods must stay on the main
  actor. Async variants made `nonisolated` (a tempting Swift 6 workaround,
  since the protocol isn't main-actor) finish on a background thread, so
  their completion handler does too; when a tap brings the app to the
  foreground, UIKit then takes its state-restoration snapshot off the main
  thread and aborts (`_performBlockAfterCATransactionCommitSynchronizes`
  assertion). Taps while the app is already open don't snapshot and work,
  which hides the bug. Use a `@preconcurrency` conformance with main-actor
  methods. Verified October 2026 in the simulator with `simctl push`.
- Push identity verification needs a server that can vouch for who owns a
  distinct id; with anonymous, device-generated ids it proves nothing, so it
  stays disabled for this package's audience.

The posthog-ios 3.69.0 requirement belongs to the app's push setup. Do not add
posthog-ios as a package dependency to enforce it: SPM would constrain every
consumer, and the zero-dependency design is deliberate (see Architecture).

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

## Identity model

Ticket access is keyed solely to the Keychain-stored `widget_session_id`.
Email and name are labels: collected optionally, never verified, and never
used to link people. Two users who type the same address stay separate
persons with separate tickets, and neither can read the other's — a fake or
borrowed address costs the sender their reply, not someone else's privacy.

The one real exposure is the reverse: PostHog emails replies to whatever
address was given, so an address typed by mistake sends that conversation's
content to its owner. There is no mitigation short of verification, which
the widget protocol does not offer; it is worth knowing before wiring the
address into anything beyond support.

A host writing `email`/`name` to the person profile (see the README's
`onEvent` recipe) is setting properties on the existing anonymous person —
that does not identify or merge anyone either. Using an address as a
`distinct_id` via `identify()` would, so don't.

## Testing

`Tests/` pins the protocol with fixtures captured from live API responses
(not hand-written). If a test breaks after a PostHog change, update the
fixture from a real response and adjust the models — the fixtures are the
source of truth for what the server actually returns.
