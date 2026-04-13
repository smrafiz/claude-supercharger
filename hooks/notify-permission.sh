#!/usr/bin/env bash
# Claude Supercharger — Permission Request Notification
# Event: PermissionRequest
# Notifies when Claude needs permission to run a tool.
# Runs AFTER smart-approve — only fires for tools that weren't auto-approved.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)

# Build a preview of what Claude wants to do
PREVIEW=$(printf '%s\n' "$INPUT" | jq -r '
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

TITLE="Claude — Permission Needed"
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
