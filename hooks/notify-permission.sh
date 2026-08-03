#!/usr/bin/env bash
# Claude Supercharger — Permission Request Notification
# Event: PermissionRequest | Matcher: (none)
# Only fires for tools not auto-approved by smart-approve.

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
source "$HOOKS_DIR/notify-helper.sh"
source "$HOOKS_DIR/lib-smart-approve.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Suppress during subagents
_is_subagent "$_INPUT" && exit 0

# v2.7.32: don't notify for permissions smart-approve auto-approves — the user
# never has to act on those, so a "Permission Needed" ping is pure noise. Uses
# the SAME verdict as smart-approve.sh so the two can't drift.
smart_approve_verdict "$_INPUT" && exit 0

# Cooldown (7s — permission requests can cluster)
_NP_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
_cooldown_ok "permission" 7 "$_NP_SID" || exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || true)

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
