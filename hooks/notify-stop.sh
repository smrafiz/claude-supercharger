#!/usr/bin/env bash
# Claude Supercharger — Task Complete Notification
# Event: Stop
# Shows prompt + response summary with git branch.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/notify-helper.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

_INPUT=$(cat)

# Skip if stop hook already active (prevent double notification)
STOP_ACTIVE=$(printf '%s\n' "$_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Suppress during subagents
_is_subagent "$_INPUT" && exit 0

# Cooldown (12s — task complete notifications)
_cooldown_ok "stop" 12 || exit 0

# Extract transcript path
TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

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

# Extract elapsed time
DURATION_MS=$(printf '%s\n' "$_INPUT" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
DURATION_MS="${DURATION_MS:-0}"
MINS=$((DURATION_MS / 60000))
SECS=$(( (DURATION_MS % 60000) / 1000 ))
if [ "$MINS" -gt 0 ]; then
  ELAPSED=" (${MINS}m ${SECS}s)"
elif [ "$SECS" -gt 0 ]; then
  ELAPSED=" (${SECS}s)"
else
  ELAPSED=""
fi

if [ -n "$QUERY" ] && [ -n "$RESPONSE" ]; then
  MSG="\"${QUERY}\" → ${RESPONSE}"
elif [ -n "$RESPONSE" ]; then
  MSG="$RESPONSE"
else
  MSG="Task completed"
fi

# Add cost to notification if available
COST_INFO=""
if [ -f "$HOME/.claude/supercharger/scope/.session-cost" ]; then
  COST_DISPLAY=$(python3 -c "import json; c=json.load(open('$HOME/.claude/supercharger/scope/.session-cost')); print(f'\${c.get(\"total_usd\",0):.2f}')" 2>/dev/null || echo "")
  [ -n "$COST_DISPLAY" ] && COST_INFO=" — ${COST_DISPLAY} this session"
fi

_send_notification "Claude — Done${ELAPSED}" "${MSG}${COST_INFO}"

exit 0
