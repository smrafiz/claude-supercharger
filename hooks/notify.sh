#!/usr/bin/env bash
# Claude Supercharger — Idle Input Notification
# Event: Notification | Matcher: idle_prompt

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/notify-helper.sh"
# shellcheck source=hooks/lib-suppress.sh
. "${BASH_SOURCE[0]%/*}/lib-suppress.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0
check_hook_disabled "notify" && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' PAYLOAD || true; PAYLOAD="${PAYLOAD%"${PAYLOAD##*[!$'\n']}"}"

# Suppress during subagents
_is_subagent "$PAYLOAD" && exit 0

# Longer cooldown (60s) — idle_prompt fires too frequently during normal processing
_cooldown_ok "idle" 60 || exit 0

MSG=$(printf '%s\n' "$PAYLOAD" | jq -r '.message // empty' 2>/dev/null || true)
[ -z "$MSG" ] && MSG="Claude Code needs your input"

# Skip if message looks like a transient processing state, not genuine input needed
MSG_LOWER=$(printf '%s\n' "$MSG" | tr '[:upper:]' '[:lower:]')
if [[ "$MSG_LOWER" =~ (processing|thinking|running|executing|compiling|loading) ]]; then
  exit 0
fi

_send_notification "Claude — Input Needed" "$MSG"

# Webhook
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  webhook_enabled && send_webhook "$MSG" || true
fi

exit 0
