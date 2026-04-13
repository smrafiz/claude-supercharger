#!/usr/bin/env bash
# Claude Supercharger — Task Complete Notification
# Event: Stop
# Shows prompt + response summary with git branch.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/notify-helper.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

INPUT=$(cat)

# Skip if stop hook already active (prevent double notification)
STOP_ACTIVE=$(printf '%s\n' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Suppress during subagents
_is_subagent "$INPUT" && exit 0

# Cooldown (12s — task complete notifications)
_cooldown_ok "stop" 12 || exit 0

# Extract transcript path
TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

QUERY=""
RESPONSE=""

# Small delay — Stop fires before transcript is fully flushed
sleep 0.3

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  QUERY=$(jq -rs '
    [.[] | select(.type == "user") |
     if .message.content | type == "string" then .
     elif [.message.content[] | select(.type == "text")] | length > 0 then .
     else empty end
    ] | last |
    if .message.content | type == "array"
    then [.message.content[] | select(.type == "text") | .text] | join(" ")
    else .message.content // empty end
  ' "$TRANSCRIPT" 2>/dev/null || echo "")

  RESPONSE=$(jq -rs '
    [.[] | select(.type == "assistant" and .message.content)] | last |
    [.message.content[] | select(.type == "text") | .text] | join(" ")
  ' "$TRANSCRIPT" 2>/dev/null || echo "")

  [ ${#QUERY} -gt 60 ] && QUERY="${QUERY:0:57}..."
  [ ${#RESPONSE} -gt 150 ] && RESPONSE="${RESPONSE:0:147}..."
fi

if [ -n "$QUERY" ] && [ -n "$RESPONSE" ]; then
  MSG="\"${QUERY}\" → ${RESPONSE}"
elif [ -n "$RESPONSE" ]; then
  MSG="$RESPONSE"
else
  MSG="Task completed"
fi

_send_notification "Claude — Task Complete" "$MSG"

exit 0
