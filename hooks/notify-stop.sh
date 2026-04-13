#!/usr/bin/env bash
# Claude Supercharger — Task Complete Notification
# Event: Stop
# Notifies when Claude completes a task, showing prompt + response summary.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

INPUT=$(cat)

# Skip if stop hook already active (prevent double notification)
STOP_ACTIVE=$(printf '%s\n' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Extract transcript path
TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

QUERY=""
RESPONSE=""

# Small delay — Stop fires before transcript is fully flushed
sleep 0.3

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Last user prompt (text content, not tool results)
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

  # Last assistant response
  RESPONSE=$(jq -rs '
    [.[] | select(.type == "assistant" and .message.content)] | last |
    [.message.content[] | select(.type == "text") | .text] | join(" ")
  ' "$TRANSCRIPT" 2>/dev/null || echo "")

  # Truncate
  [ ${#QUERY} -gt 60 ] && QUERY="${QUERY:0:57}..."
  [ ${#RESPONSE} -gt 150 ] && RESPONSE="${RESPONSE:0:147}..."
fi

# Build message
if [ -n "$QUERY" ] && [ -n "$RESPONSE" ]; then
  MSG="\"${QUERY}\" → ${RESPONSE}"
elif [ -n "$RESPONSE" ]; then
  MSG="$RESPONSE"
else
  MSG="Task completed"
fi

TITLE="Claude — Task Complete"
SAFE_MSG=$(printf '%s' "$MSG" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g" | head -c 200)

if [ -f "$SUPERCHARGER_DIR/.sound-only-notify" ]; then
  printf '\a'
elif [[ "$OSTYPE" == "darwin"* ]]; then
  osascript -e "display notification \"$SAFE_MSG\" with title \"$TITLE\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "$TITLE" "$MSG" 2>/dev/null || true
else
  printf '\a'
fi

exit 0
