#!/usr/bin/env bash
# Claude Supercharger — Notification Hook
# Event: Notification
# Sends desktop notifications for idle prompts.

set -euo pipefail

PAYLOAD=$(cat)
MSG=$(printf '%s\n' "$PAYLOAD" | jq -r '.message // empty' 2>/dev/null)
[ -z "$MSG" ] && MSG="Claude Code needs your input"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"

# Check disable flags
[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

# Cooldown — skip if last notification was within 30 seconds
LAST_NOTIFY="$SCOPE_DIR/.last-idle-notify"
if [ -f "$LAST_NOTIFY" ]; then
  LAST_TS=$(cat "$LAST_NOTIFY" 2>/dev/null || echo "0")
  [ -z "$LAST_TS" ] && LAST_TS=0
  NOW=$(date +%s)
  DIFF=$((NOW - LAST_TS))
  [ "$DIFF" -lt 30 ] && exit 0
fi
mkdir -p "$SCOPE_DIR" 2>/dev/null || true
date +%s > "$LAST_NOTIFY" 2>/dev/null || true

TITLE="Claude — Input Needed"

# Sanitize for osascript
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

# Webhook
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  webhook_enabled && send_webhook "$MSG" || true
fi

exit 0
