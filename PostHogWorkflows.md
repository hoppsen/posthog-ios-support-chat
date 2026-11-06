# PostHog workflows for reply notifications

Setup and verification guide for pushing support replies to customers' devices. It is written so that a person or an agent with PostHog MCP access can follow it step by step. The README's **Push notifications for replies** section explains the design; this file is the procedure.

## How a reply reaches the device

```
Team replies in the inbox
  → $conversation_message_sent        (belongs to the team member)
      → Workflow "Support reply → push (iOS)":
          Get ticket → push to the ticket's customer
```

One workflow. The reply event belongs to the team member who replied, but the push step sends to whatever its **Distinct ID** input names, so the workflow looks up the ticket and pushes to the customer's distinct id. The push leaves within seconds of the reply.

Until November 2026 this took two workflows, because the push step ignored its Distinct ID input and delivered to the run's own person ([PostHog/posthog#120326](https://github.com/PostHog/posthog/issues/120326)). PostHog fixed that in [#120237](https://github.com/PostHog/posthog/pull/120237), deployed 2026-10-22. If you still run the old pair ("Support reply → customer event" plus "Support reply push (iOS)"), see **Migrating from the two-workflow setup** at the end.

## Prerequisites

- **The app:** posthog-ios **3.69.0+**, the Push Notifications capability, and the app wiring from the README (`offersReplyNotifications: true`, `refreshPushRegistration()`, notification delegate). `SupportChatContextProvider.distinctId` must return `PostHogSDK.shared.getDistinctId()`.
- **The PostHog project:** Support enabled, and an **APNs channel** (Workflows → Channels) for the app's bundle id. Create a production channel; a sandbox channel is only for testing builds run from Xcode. Leave **Identity verification** disabled for anonymous users.

## 1. Find the channel id

List the project's APNs integrations (MCP: `integrations-list` with `kind: "apns"`; use `firebase` for FCM) and take the **production** channel's `id`. In a live workflow, select only production. Tokens carry no APNs environment, so a sandbox channel next to it makes every push also go to the wrong environment and log a `BadDeviceToken` error.

## 2. Create the workflow

MCP: `workflows-create` with this body. It is created as a draft. Replace `<APNS_CHANNEL_ID>` with the id from step 1.

```json
{
  "name": "Support reply → push (iOS)",
  "description": "When the team replies to a widget ticket, looks up the ticket and pushes the reply straight to the customer's device.",
  "status": "draft",
  "exit_condition": "exit_only_at_end",
  "actions": [
    {
      "id": "trigger_node",
      "name": "Team replied to a widget ticket",
      "type": "trigger",
      "config": {
        "type": "event",
        "filters": {
          "events": [
            {
              "id": "$conversation_message_sent",
              "name": "$conversation_message_sent",
              "type": "events",
              "order": 0,
              "properties": [
                { "key": "channel_source", "value": ["widget"], "operator": "exact", "type": "event" },
                { "key": "author_type", "value": ["team"], "operator": "exact", "type": "event" }
              ]
            }
          ],
          "filter_test_accounts": false
        }
      }
    },
    {
      "id": "get_ticket",
      "name": "Get ticket",
      "type": "function",
      "on_error": "abort",
      "config": {
        "template_id": "template-posthog-get-ticket",
        "inputs": { "ticket_id": { "value": "{event.properties.ticket_id}" } }
      },
      "output_variable": { "key": "ticket" }
    },
    {
      "id": "push_customer",
      "name": "Push reply to customer",
      "type": "function_push",
      "on_error": "continue",
      "config": {
        "template_id": "template-native-push",
        "message_category_type": "transactional",
        "inputs": {
          "distinctId": { "value": "{variables.ticket.distinct_id}" },
          "channels": { "value": [<APNS_CHANNEL_ID>] },
          "title": { "value": "New reply from support" },
          "body": { "value": "{{ event.properties.message_content | replace: \"\\\\\", \"\" | strip_html | truncate: 180 }}", "templating": "liquid" },
          "data": { "value": { "type": "support_reply", "ticket_id": "{event.properties.ticket_id}" } },
          "ios_sound": { "value": "default" },
          "ios_badge": { "value": 1 },
          "ios_threadId": { "value": "support-{event.properties.ticket_id}" },
          "ios_interruptionLevel": { "value": "active" }
        }
      }
    },
    { "id": "exit_node", "name": "Exit", "type": "exit", "config": { "reason": "Done" } }
  ],
  "edges": [
    { "from": "trigger_node", "to": "get_ticket", "type": "continue" },
    { "from": "get_ticket", "to": "push_customer", "type": "continue" },
    { "from": "push_customer", "to": "exit_node", "type": "continue" }
  ]
}
```

Notes on the push step:

- **Distinct ID** is the ticket's `distinct_id` from the Get ticket step: the id the app sent when the ticket was created, which is also the id posthog-ios registered the device under. The reply event now also carries `customer_distinct_id`, so `{event.properties.customer_distinct_id}` works too; the lookup is kept because it is the documented path.
- **Templating differs per input.** `body` is Liquid: `{{ … }}` with `"templating": "liquid"`. Every other input is Hog: `{…}`. The wrong brace style is sent as literal text, without an error.
- **The body** strips the backslashes the inbox editor adds before punctuation (`\.`, `\!`, `\[`), drops HTML, and puts up to 180 characters of the reply on the lock screen. A backslash someone actually typed is lost from the preview too, never from the chat. Markdown links and `**bold**` still show as written. Use a generic text such as "You have a new reply" if replies may be sensitive.
- **The custom data keys** (`type: support_reply`, `ticket_id`) must match `SupportChatNotification`. PostHog places them at the top level of the APNs payload.
- **The badge** is set to 1. The app should clear it when the chat opens.
- **`on_error: continue`** on the push step: a customer without a registered device must not fail the run.
- **Never send** `bytecode`, `order` or a top-level `trigger`; the server compiles and derives those.

## 3. Test before enabling

Test-run step by step (MCP: `workflows-test-run`, one step per call, feeding the returned `nextActionId` back as `current_action_id`):

1. **Trigger:** an event shaped like a real reply must return `success`, not `skipped`:
   ```json
   { "event": { "event": "$conversation_message_sent", "distinct_id": "<team member>",
     "properties": { "ticket_id": "<real ticket id>", "ticket_number": 1, "channel_source": "widget",
                     "author_type": "team", "message_id": "test", "message_content": "Test reply\\." } } }
   ```
2. **Get ticket:** run it with `mock_async_functions: false` against a real ticket id. It only reads. The stored `ticket` variable must contain the customer's `distinct_id`.
3. **Push:** pass the same event plus `"variables": { "ticket": { "distinct_id": "<customer id>" } }` in `globals`. With the default mocks, the log prints the `sendPushNotification` call: check that `distinctId` is the customer's id and the body has no backslashes. With `mock_async_functions: false` this sends a **real** push; only do that to your own test device.

Then enable the workflow (`workflows-enable`) with the project owner's approval, and reply to a test ticket from the inbox.

## 4. Verify end to end

- **The device registered:** the customer's person has a `$device_push_subscription_<bundle id>:<hash>` property, holding the encrypted token. It can appear a launch after permission was granted.
- **The push was sent:** the workflow's log (`workflows-logs`, search `push`) shows `Push notification accepted by APNs for 1 of N device(s).` Accepted means handed to Apple; APNs reports no delivery or open. A `BadDeviceToken` line next to it is a second token from the other APNs environment (see below) and does not stop the send to the right one.

## Troubleshooting

| Log or symptom | Meaning | Fix |
|---|---|---|
| `No active APNS device token found for distinct_id: <id>` | The customer named by Distinct ID has no token. | Check the person for a `$device_push_subscription_…` property; without one, the app has not registered (posthog-ios < 3.69.0, no permission, or not relaunched yet). |
| `BadDeviceToken` | A token belongs to the other APNs environment. | Builds run from Xcode use sandbox; TestFlight and App Store builds use production. Select the channel that matches. A user who ran both kinds of build has one token of each; the right one is still delivered. |
| `InvalidProviderToken` (403) | Apple rejected the signing credentials. | If PostHog adds that the key delivered recently, it retries on its own; otherwise check the key id, team id and signing key in the channel. |
| Trigger test returns `skipped` | The test event does not match the trigger's filters. | Fix the test payload; on a real copied payload, fix the filter. |
| Push step logs the team member's id | `distinctId` still reads `{event.distinct_id}`. | Use `{variables.ticket.distinct_id}` (or `{event.properties.customer_distinct_id}`). |
| Push arrives but tapping does nothing | The custom data keys don't match, or the app's notification delegate isn't set before launch finishes. | Compare the data with `SupportChatNotification`; set the delegate in `didFinishLaunching`. |

## Migrating from the two-workflow setup

The pre-November-2026 recipe used workflow A ("Support reply → customer event": Get ticket → capture `support:reply_received` for the customer) and workflow B ("Support reply push (iOS)": that event → push). To collapse them:

1. In workflow A, add the push step above after Get ticket (`workflows-patch-graph`: `add_action`, re-point Get ticket's edge to it, edge from it to Exit). Leave the capture step in place and publish: the next reply then produces two pushes, one from A within seconds and one from B a minute or two later.
2. Confirm in workflow A's log that its push step was accepted by APNs.
3. Remove the capture step (`remove_action`), publish, and archive workflow B (`workflows-archive`). With nothing capturing `support:reply_received`, B never fires even if it stays active.

Nothing changes in the app or the package.
