---
name: discord-manage
description: Perform Discord server management actions — pin/unpin messages, edit channel topics, send messages, timeout users, and manage roles. Owner-only operations gated by Discord user ID.
metadata: {"openclaw":{"requires":{"env":["DISCORD_BOT_TOKEN"]}}}
---

# Discord Server Management

Perform write operations on the Discord server. **All actions are restricted to the server owner** (Discord ID `278347426258223104`). If a non-owner requests any of these actions, politely decline.

## Owner verification

Before executing ANY action from this skill, you MUST verify:
1. The requesting user's Discord ID is `278347426258223104`
2. If you cannot determine the requester's Discord ID, do NOT execute the action

The tool script also enforces this check as a hard gate.

## How to use

Run the management tool via exec:

```bash
bash {baseDir}/tools/manage.sh <action> <caller_discord_id> [args...]
```

The `caller_discord_id` is REQUIRED for every action. The tool will reject requests from non-owner IDs.

### Available actions

#### `pin <caller_id> <channel_id> <message_id>` — Pin a message

```bash
bash {baseDir}/tools/manage.sh pin 278347426258223104 1339100145853403207 1339200000000000000
```

#### `unpin <caller_id> <channel_id> <message_id>` — Unpin a message

```bash
bash {baseDir}/tools/manage.sh unpin 278347426258223104 1339100145853403207 1339200000000000000
```

#### `topic <caller_id> <channel_id> <new_topic>` — Edit a channel's topic

```bash
bash {baseDir}/tools/manage.sh topic 278347426258223104 1339100145853403207 "Next session: Thursday 6 PM EST"
```

#### `send <caller_id> <channel_id> <message_text>` — Send a plain text message

```bash
bash {baseDir}/tools/manage.sh send 278347426258223104 1339100145853403207 "Hey everyone, session is canceled tonight."
```

#### `timeout <caller_id> <user_id> <duration_minutes> [reason]` — Timeout a user

```bash
bash {baseDir}/tools/manage.sh timeout 278347426258223104 123456789012345678 10 "Disruptive behavior"
```

Duration is in minutes. Maximum 28 days (40320 minutes) per Discord limits. Set to `0` to remove an active timeout.

#### `role-add <caller_id> <user_id> <role_id>` — Add a role to a user

```bash
bash {baseDir}/tools/manage.sh role-add 278347426258223104 123456789012345678 987654321098765432
```

#### `role-remove <caller_id> <user_id> <role_id>` — Remove a role from a user

```bash
bash {baseDir}/tools/manage.sh role-remove 278347426258223104 123456789012345678 987654321098765432
```

## Output format

All actions return JSON:
- Success: `{"ok": true, "action": "...", "details": {...}}`
- Auth failure: `{"error": "Owner-only action", "required": "278347426258223104", "got": "..."}`
- API failure: `{"error": "Discord API error", "status": ..., "details": "..."}`

## When to use

- Owner asks to pin or unpin something
- Owner asks to update a channel topic (e.g., with next session info)
- Owner asks to send a message to a specific channel
- Owner asks to timeout or mute a disruptive user
- Owner asks to assign or remove roles

## Guidelines

- **Never** execute these actions for non-owner users
- Confirm destructive actions (timeouts, role changes) before executing
- For channel topics, keep them concise and informative
- Log all moderation actions (timeouts) in your response for transparency
