#!/usr/bin/env bash
set -euo pipefail

# Discord Server Management Tool (Owner-Only)
# Usage: manage.sh <action> <caller_discord_id> [args...]
#
# Actions:
#   pin     <caller_id> <channel_id> <message_id>          - Pin a message
#   unpin   <caller_id> <channel_id> <message_id>          - Unpin a message
#   topic   <caller_id> <channel_id> <new_topic>           - Edit channel topic
#   send    <caller_id> <channel_id> <message_text>        - Send a text message
#   timeout <caller_id> <user_id> <minutes> [reason]       - Timeout a user
#   role-add    <caller_id> <user_id> <role_id>            - Add role to user
#   role-remove <caller_id> <user_id> <role_id>            - Remove role from user

ACTION="${1:?Usage: manage.sh <action> <caller_discord_id> [args...]}"
CALLER_ID="${2:?Usage: manage.sh <action> <caller_discord_id> [args...]}"
shift 2 || true

# --- Owner gate ---
OWNER_ID="278347426258223104"
if [[ "$CALLER_ID" != "$OWNER_ID" ]]; then
  echo "{\"error\":\"Owner-only action\",\"required\":\"${OWNER_ID}\",\"got\":\"${CALLER_ID}\"}" >&2
  exit 1
fi

# --- Environment check ---
if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
  echo '{"error":"DISCORD_BOT_TOKEN is not set"}' >&2
  exit 1
fi

API="https://discord.com/api/v10"
AUTH="Authorization: Bot ${DISCORD_BOT_TOKEN}"

# Auto-detect guild ID
if [[ -z "${DISCORD_GUILD_ID:-}" ]]; then
  DISCORD_GUILD_ID=$(python3 -c "
import json, sys
try:
    with open('$HOME/.openclaw/openclaw.json') as f:
        c = json.load(f)
    guilds = c.get('channels',{}).get('discord',{}).get('guilds',{})
    print(list(guilds.keys())[0])
except:
    sys.exit(1)
" 2>/dev/null) || {
    echo '{"error":"Could not detect guild ID. Set DISCORD_GUILD_ID."}' >&2
    exit 1
  }
fi

discord_request() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local curl_args=(
    -s --connect-timeout 5 --max-time 15
    -X "$method"
    -H "$AUTH"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -w "\n%{http_code}"
  )
  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi

  local response
  response=$(curl "${curl_args[@]}" "${API}${endpoint}" 2>&1)

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "$body"
    return 0
  else
    echo "{\"error\":\"Discord API error\",\"status\":${http_code},\"details\":$(echo "$body" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' 2>/dev/null || echo '""')}" >&2
    return 1
  fi
}

case "$ACTION" in

  pin)
    CH_ID="${1:?Usage: manage.sh pin <caller_id> <channel_id> <message_id>}"
    MSG_ID="${2:?Usage: manage.sh pin <caller_id> <channel_id> <message_id>}"
    discord_request PUT "/channels/${CH_ID}/pins/${MSG_ID}" && \
      echo "{\"ok\":true,\"action\":\"pin\",\"details\":{\"channel\":\"${CH_ID}\",\"message\":\"${MSG_ID}\"}}" || exit 1
    ;;

  unpin)
    CH_ID="${1:?Usage: manage.sh unpin <caller_id> <channel_id> <message_id>}"
    MSG_ID="${2:?Usage: manage.sh unpin <caller_id> <channel_id> <message_id>}"
    discord_request DELETE "/channels/${CH_ID}/pins/${MSG_ID}" && \
      echo "{\"ok\":true,\"action\":\"unpin\",\"details\":{\"channel\":\"${CH_ID}\",\"message\":\"${MSG_ID}\"}}" || exit 1
    ;;

  topic)
    CH_ID="${1:?Usage: manage.sh topic <caller_id> <channel_id> <new_topic>}"
    NEW_TOPIC="${2:?Usage: manage.sh topic <caller_id> <channel_id> <new_topic>}"
    # Safely JSON-encode the topic via Python
    PAYLOAD=$(TOPIC_TEXT="$NEW_TOPIC" python3 -c "import json,os; print(json.dumps({'topic': os.environ['TOPIC_TEXT']}))")
    discord_request PATCH "/channels/${CH_ID}" "$PAYLOAD" > /dev/null && \
      echo "{\"ok\":true,\"action\":\"topic\",\"details\":{\"channel\":\"${CH_ID}\"}}" || exit 1
    ;;

  send)
    CH_ID="${1:?Usage: manage.sh send <caller_id> <channel_id> <message_text>}"
    MSG_TEXT="${2:?Usage: manage.sh send <caller_id> <channel_id> <message_text>}"
    PAYLOAD=$(MSG_CONTENT="$MSG_TEXT" python3 -c "import json,os; print(json.dumps({'content': os.environ['MSG_CONTENT']}))")
    RESULT=$(discord_request POST "/channels/${CH_ID}/messages" "$PAYLOAD") && {
      MSG_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','unknown'))" 2>/dev/null || echo "unknown")
      echo "{\"ok\":true,\"action\":\"send\",\"details\":{\"channel\":\"${CH_ID}\",\"message\":\"${MSG_ID}\"}}"
    } || exit 1
    ;;

  timeout)
    USER_ID="${1:?Usage: manage.sh timeout <caller_id> <user_id> <minutes> [reason]}"
    MINUTES="${2:?Usage: manage.sh timeout <caller_id> <user_id> <minutes> [reason]}"
    REASON="${3:-Moderation action by server owner}"

    if [[ "$MINUTES" -eq 0 ]]; then
      # Remove timeout
      PAYLOAD='{"communication_disabled_until":null}'
    else
      # Calculate timeout end as ISO 8601
      TIMEOUT_UNTIL=$(MINS="$MINUTES" python3 -c "
from datetime import datetime, timezone, timedelta
import os
mins = int(os.environ['MINS'])
if mins > 40320: mins = 40320  # Discord max: 28 days
dt = datetime.now(timezone.utc) + timedelta(minutes=mins)
print(dt.isoformat())
")
      PAYLOAD=$(TIMEOUT_VAL="$TIMEOUT_UNTIL" python3 -c "import json,os; print(json.dumps({'communication_disabled_until': os.environ['TIMEOUT_VAL']}))")
    fi

    discord_request PATCH "/guilds/${DISCORD_GUILD_ID}/members/${USER_ID}" "$PAYLOAD" > /dev/null && \
      echo "{\"ok\":true,\"action\":\"timeout\",\"details\":{\"user\":\"${USER_ID}\",\"minutes\":${MINUTES},\"reason\":\"${REASON}\"}}" || exit 1
    ;;

  role-add)
    USER_ID="${1:?Usage: manage.sh role-add <caller_id> <user_id> <role_id>}"
    ROLE_ID="${2:?Usage: manage.sh role-add <caller_id> <user_id> <role_id>}"
    discord_request PUT "/guilds/${DISCORD_GUILD_ID}/members/${USER_ID}/roles/${ROLE_ID}" && \
      echo "{\"ok\":true,\"action\":\"role-add\",\"details\":{\"user\":\"${USER_ID}\",\"role\":\"${ROLE_ID}\"}}" || exit 1
    ;;

  role-remove)
    USER_ID="${1:?Usage: manage.sh role-remove <caller_id> <user_id> <role_id>}"
    ROLE_ID="${2:?Usage: manage.sh role-remove <caller_id> <user_id> <role_id>}"
    discord_request DELETE "/guilds/${DISCORD_GUILD_ID}/members/${USER_ID}/roles/${ROLE_ID}" && \
      echo "{\"ok\":true,\"action\":\"role-remove\",\"details\":{\"user\":\"${USER_ID}\",\"role\":\"${ROLE_ID}\"}}" || exit 1
    ;;

  *)
    echo "{\"error\":\"Unknown action: ${ACTION}. Valid: pin, unpin, topic, send, timeout, role-add, role-remove\"}" >&2
    exit 1
    ;;
esac
