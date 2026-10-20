# PostHog workflows for reply notifications

Setup and verification guide for pushing support replies to customers' devices. It is written so that a person or an agent with PostHog MCP access can follow it step by step. The README's **Push notifications for replies** section explains the design; this file is the procedure.

## Why two workflows

A push step delivers to the person the workflow **run** belongs to. Its required "Distinct ID" input is only used in log messages ([PostHog/posthog#120326](https://github.com/PostHog/posthog/issues/120326), fix in review as [#120237](https://github.com/PostHog/posthog/pull/120237)). Every Support event belongs to the team member who replied, so the reply is handed to the customer through an event captured for them:

```
Team replies in the inbox
  → $conversation_message_sent        (belongs to the team member)
      → Workflow A: Get ticket → capture support:reply_received for the customer
          → support:reply_received    (belongs to the customer)
              → Workflow B: push to the customer's device
```

The hand-off goes through event ingestion, so expect **a minute or two** between the reply and the push.

## Prerequisites

- **The app:** posthog-ios **3.69.0+**, the Push Notifications capability, and the app wiring from the README (permission, `registerForRemoteNotifications()`, notification delegate). `SupportChatContextProvider.distinctId` must return `PostHogSDK.shared.getDistinctId()`.
- **The PostHog project:** Support enabled, and an **APNs channel** (Workflows → Channels) for the app's bundle id. Create a production channel; a sandbox channel is only for testing builds run from Xcode. Leave **Identity verification** disabled for anonymous users.

## 1. Find the channel id

List the project's APNs integrations (MCP: `integrations-list` with `kind: "apns"`; use `firebase` for FCM) and take the **production** channel's `id`. In a live workflow, select only production. Tokens carry no APNs environment, so a sandbox channel next to it makes every push also go to the wrong environment and log a `BadDeviceToken` error.

## 2. Create workflow A: reply → customer event

MCP: `workflows-create` with this body. It is created as a draft.

```json
{
  "name": "Support reply → customer event",
  "description": "Captures support:reply_received for the customer when the team replies to a widget ticket. The reply event belongs to the team member; the push workflow triggers on this customer event instead.",
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
      "id": "capture_reply",
      "name": "Capture reply for the customer",
      "type": "function",
      "on_error": "abort",
      "config": {
        "template_id": "template-posthog-capture",
        "inputs": {
          "event": { "value": "support:reply_received" },
          "distinct_id": { "value": "{variables.ticket.distinct_id}" },
          "properties": {
            "value": {
              "ticket_id": "{event.properties.ticket_id}",
              "ticket_number": "{event.properties.ticket_number}",
              "message_id": "{event.properties.message_id}",
              "message_content": "{event.properties.message_content}",
              "channel_source": "{event.properties.channel_source}"
            }
          }
        }
      }
    },
    { "id": "exit_node", "name": "Exit", "type": "exit", "config": { "reason": "Done" } }
  ],
  "edges": [
    { "from": "trigger_node", "to": "get_ticket", "type": "continue" },
    { "from": "get_ticket", "to": "capture_reply", "type": "continue" },
    { "from": "capture_reply", "to": "exit_node", "type": "continue" }
  ]
}
```

## 3. Create workflow B: push to the customer

Replace `<APNS_CHANNEL_ID>` with the id from step 1.

```json
{
  "name": "Support reply push (iOS)",
  "description": "Pushes a support reply to the customer's device. Triggered by support:reply_received, which 'Support reply → customer event' captures for the customer.",
  "status": "draft",
  "exit_condition": "exit_only_at_end",
  "actions": [
    {
      "id": "trigger_node",
      "name": "Customer received a support reply",
      "type": "trigger",
      "config": {
        "type": "event",
        "filters": {
          "events": [{ "id": "support:reply_received", "name": "support:reply_received", "type": "events", "order": 0 }],
          "filter_test_accounts": false
        }
      }
    },
    {
      "id": "push_reply",
      "name": "Push reply to customer",
      "type": "function_push",
      "config": {
        "template_id": "template-native-push",
        "message_category_type": "transactional",
        "inputs": {
          "distinctId": { "value": "{event.distinct_id}" },
          "channels": { "value": [<APNS_CHANNEL_ID>] },
          "title": { "value": "New reply from support" },
          "body": { "value": "{{ event.properties.message_content | strip_html | truncate: 180 }}", "templating": "liquid" },
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
    { "from": "trigger_node", "to": "push_reply", "type": "continue" },
    { "from": "push_reply", "to": "exit_node", "type": "continue" }
  ]
}
```

Notes on the push step:

- **Templating differs per input.** `body` is Liquid: `{{ … }}` with `"templating": "liquid"`. Every other input is Hog: `{…}`. The wrong brace style is sent as literal text, without an error.
- **The custom data keys** (`type: support_reply`, `ticket_id`) must match `SupportChatNotification`. PostHog places them at the top level of the APNs payload.
- **The body** puts up to 180 characters of the reply on the lock screen. Use a generic text such as "You have a new reply" if replies may be sensitive. Inbox replies are markdown, so escapes such as `\.` can show; Liquid rejects backslashes, so they cannot be stripped here.
- **The badge** is set to 1. The app should clear it when the chat opens.
- **Never send** `bytecode`, `order` or a top-level `trigger`; the server compiles and derives those.

## 4. Test before enabling

Test-run step by step (MCP: `workflows-test-run`, one step per call, feeding the returned `nextActionId` back as `current_action_id`):

1. **Workflow A, trigger:** an event shaped like a real reply must return `success`, not `skipped`:
   ```json
   { "event": { "event": "$conversation_message_sent", "distinct_id": "<team member>",
     "properties": { "ticket_id": "<real ticket id>", "ticket_number": 1, "channel_source": "widget",
                     "author_type": "team", "message_id": "test", "message_content": "Test reply" } } }
   ```
2. **Workflow A, Get ticket:** run it with `mock_async_functions: false` against a real ticket id. It only reads. The stored `ticket` variable must contain the customer's `distinct_id`.
3. **Workflow A, capture:** pass `globals.variables.ticket.distinct_id`; the step must complete.
4. **Workflow B, push:** the push step reads tokens from `globals.person`, so a realistic test passes the customer's person, with its `$device_push_subscription_…` property, as `globals.person`. With `mock_async_functions: false` this sends a **real** push; only do that to your own test device.

Then enable both workflows (`workflows-enable`) with the project owner's approval, and reply to a test ticket from the inbox.

## 5. Verify end to end

- **The device registered:** the customer's person has a `$device_push_subscription_<bundle id>:<hash>` property, holding the encrypted token. It can appear a launch after permission was granted.
- **Workflow A ran:** `support:reply_received` exists for the customer's distinct id, about a second after `$conversation_message_sent`.
- **Workflow B delivered:** its log shows `Push notification accepted by APNs for 1 of 1 device(s).` Accepted means handed to Apple; APNs reports no delivery or open.

## Troubleshooting

| Log or symptom | Meaning | Fix |
|---|---|---|
| `No active APNS device token found for distinct_id: <id>` | The **run's person** has no token. The id printed is the step's Distinct ID input, which may be a different person. | Check that the run belongs to the customer (workflow B, not A). Check the person for a `$device_push_subscription_…` property; without one, the app has not registered (posthog-ios < 3.69.0, no permission, or not relaunched yet). |
| `BadDeviceToken` | The token belongs to the other APNs environment. | Builds run from Xcode use sandbox; TestFlight and App Store builds use production. Select the channel that matches. |
| `InvalidProviderToken` (403) | Apple rejected the signing credentials. | If PostHog adds that the key delivered recently, it retries on its own; otherwise check the key id, team id and signing key in the channel. |
| Trigger test returns `skipped` | The test event does not match the trigger's filters. | Fix the test payload; on a real copied payload, fix the filter. |
| Workflow B never starts | `support:reply_received` was not captured, or ingestion is slow. | Check workflow A's log for the capture step; wait a couple of minutes. |
| Push arrives but tapping does nothing | The custom data keys don't match, or the app's notification delegate isn't set before launch finishes. | Compare the data with `SupportChatNotification`; set the delegate in `didFinishLaunching`. |

## When PostHog fixes the push step

Once [#120237](https://github.com/PostHog/posthog/pull/120237) is deployed, the push step honors its Distinct ID, and this becomes one workflow: in workflow A, add the push step after Get ticket with `distinctId: {variables.ticket.distinct_id}`, then delete workflow B. The capture step can stay for analytics. Nothing changes in the app or the package.
