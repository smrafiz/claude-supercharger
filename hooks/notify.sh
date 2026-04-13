#!/usr/bin/env bash
# Claude Supercharger — Idle Input Notification
# Event: Notification | Matcher: idle_prompt

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/notify-helper.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

PAYLOAD=$(cat)

# Suppress during subagents
_is_subagent "$PAYLOAD" && exit 0

# Configurable cooldown (15s default)
_cooldown_ok "idle" 15 || exit 0

MSG=$(printf '%s\n' "$PAYLOAD" | jq -r '.message // empty' 2>/dev/null)
[ -z "$MSG" ] && MSG="Claude Code needs your input"

_send_notification "Claude — Input Needed" "$MSG"

# Webhook
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  webhook_enabled && send_webhook "$MSG" || true
fi

exit 0
