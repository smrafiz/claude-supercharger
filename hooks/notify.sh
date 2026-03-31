#!/usr/bin/env bash
# Claude Supercharger — Notification Hook
# Event: Notification | Matcher: (none)
# Alerts user when Claude needs input.

set -euo pipefail

MESSAGE="Claude Code needs your input"

if [[ "$OSTYPE" == "darwin"* ]]; then
  osascript -e "display notification \"$MESSAGE\" with title \"Claude Supercharger\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "Claude Supercharger" "$MESSAGE" 2>/dev/null || true
else
  printf '\a'
fi

exit 0
