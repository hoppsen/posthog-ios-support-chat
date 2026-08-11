# Contributing

Thanks for taking a look. Issues and pull requests are welcome — especially reports from apps running this against their own PostHog project, since the underlying protocol is beta and the surface we can test alone is limited.

## Getting set up

```bash
bundle install
bundle exec fastlane setup    # installs the pre-commit hook (format + lint on staged files)
```

Tooling versions are pinned in `Mintfile` and run through [Mint](https://github.com/yonaskolb/Mint). The pre-commit hook runs SwiftFormat and SwiftLint on staged Swift files and stops the commit if either changes something — review, stage, commit again.

```bash
bundle exec fastlane lint     # SwiftLint, strict
bundle exec fastlane format   # SwiftFormat
xcodebuild test -scheme PostHogSupportChat-Package -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI runs the same lint, test, and a Release build for a generic iOS device.

## Things worth knowing before you change code

- **`CLAUDE.md` documents the protocol.** The widget API has sharp edges that are not in posthog-js's public types — the `+` in the `after` cursor, personless server events, per-endpoint `Origin` requirements, oldest-first pagination. Read it before touching `ConversationsAPI` or the polling logic, and add to it when you learn something new.
- **Tests pin real responses.** Fixtures in `Tests/` were captured from the live API. If a test breaks after a PostHog change, update the fixture from a real response rather than adjusting the assertion to fit.
- **Don't hand-edit `Localizable.xcstrings`.** Add the English string in code with `bundle: .module` and a `comment:` explaining where it appears, add the key to the catalog, then run `bundle exec fastlane translate_batch` (needs `OPENAI_API_KEY`). `bundle exec fastlane check_translations` must pass. Strings configurable in the PostHog dashboard are fallbacks only — the dashboard value always wins at runtime.
- **The transport is meant to be replaceable.** `PostHogSupportChatClient` speaks a protocol that official mobile support will eventually supersede; `PostHogSupportChat` (the UI) is the part meant to last. Keep app-facing API in terms the UI needs, not in terms of today's endpoints.
- **Every user-facing string needs `bundle: .module`** — without it the lookup silently falls back to the host app's bundle and ships untranslated.

## Pull requests

Keep changes focused, explain the user-visible effect, and say how you verified it — "tested against my project's Support inbox" is worth more here than a green CI badge, since CI cannot exercise the live API.
