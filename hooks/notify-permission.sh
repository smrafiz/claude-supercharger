#!/usr/bin/env bash
# Claude Supercharger — Permission Request Notification
# Event: PermissionRequest
# Only fires for tools not auto-approved by smart-approve.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/notify-helper.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

_INPUT=$(cat)

# Suppress during subagents
_is_subagent "$_INPUT" && exit 0

# Cooldown (7s — permission requests can cluster)
_cooldown_ok "permission" 7 || exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)

PREVIEW=$(printf '%s\n' "$_INPUT" | jq -r '
  .tool_input |
  if .command then .command
  elif .file_path then .file_path
  else (tostring | .[0:80])
  end // ""
' 2>/dev/null || echo "")

MSG="Wants to run ${TOOL_NAME}"
[ -n "$PREVIEW" ] && {
  [ ${#PREVIEW} -gt 100 ] && PREVIEW="${PREVIEW:0:97}..."
  MSG="${MSG}: ${PREVIEW}"
}

_send_notification "Claude — Permission Needed" "$MSG"

exit 0
