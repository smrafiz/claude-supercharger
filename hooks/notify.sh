#!/usr/bin/env bash
# Claude Supercharger — Notification Hook
# Event: Notification | Matcher: (none)
# Alerts user when Claude needs input.
# Sends webhook notification if configured.

set -eo pipefail

MESSAGE="Claude Code needs your attention"

NO_NOTIFY_FLAG="$HOME/.claude/supercharger/.no-desktop-notify"

# Desktop notification (skip if flag file exists or env var set)
if [[ ! -f "$NO_NOTIFY_FLAG" && "${SUPERCHARGER_NO_DESKTOP_NOTIFY:-0}" != "1" ]]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    osascript -e "display notification \"$MESSAGE\" with title \"Claude Supercharger\"" 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "Claude Supercharger" "$MESSAGE" 2>/dev/null || true
  else
    printf '\a'
  fi
fi

# Webhook notification (if configured) — uses shared webhook lib
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  if webhook_enabled; then
    send_webhook "Claude Code needs your attention" || true
  fi
fi

exit 0
