#!/usr/bin/env bash
# Claude Supercharger — Auto Compact Advisor
# Event: PostToolUse | Matcher: (none)
# Injects /compact reminders during agentic runs when context climbs.
# Fires once per threshold band (70/80/90%) — resets when context drops below 70%.
#
# Complements context-advisor.sh (UserPromptSubmit) by catching context growth
# during long agentic runs where the user isn't typing.
#
# Opt-out: add "auto-compact" to ~/.claude/supercharger/scope/.disabled-hooks
# or set {"disableHooks": ["auto-compact"]} in .supercharger.json

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "auto-compact" && exit 0

_INPUT=$(cat)
# 2.21.12: session-scope the compaction debounce band. The context window is
# per-session, but .compact-last-band was global — one session at 85% wrote
# band 80 and suppressed another session's 70/80 warning, and dropping below 70
# removed the shared file, resetting the other's debounce.
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="default"

# ── Read context percentage ───────────────────────────────────────────────────
PCT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    pct = d.get('context_window', {}).get('used_percentage', '')
    print(int(float(pct)) if pct != '' else '')
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$PCT" ] && exit 0
[ "$PCT" -lt 70 ] && {
  rm -f "$SUPERCHARGER_STATE/scope/.compact-last-band-${SID}"
  exit 0
}

# ── Determine threshold band ──────────────────────────────────────────────────
if   [ "$PCT" -ge 90 ]; then BAND=90
elif [ "$PCT" -ge 80 ]; then BAND=80
else                          BAND=70
fi

# ── Debounce: skip if already warned at this band ────────────────────────────
STATE_FILE="$SUPERCHARGER_STATE/scope/.compact-last-band-${SID}"
LAST_BAND=$(cat "$STATE_FILE" 2>/dev/null || echo "0")

[ "$BAND" -le "$LAST_BAND" ] && exit 0

# ── Write new band state ──────────────────────────────────────────────────────
mkdir -p "$SUPERCHARGER_STATE/scope"
printf '%s\n' "$BAND" > "$STATE_FILE"

# ── Compose message ───────────────────────────────────────────────────────────
case "$BAND" in
  90) MSG="[CTX CRITICAL ${PCT}%] Near context limit. Stop current task, run /compact, verify work is saved." ;;
  80) MSG="[CTX HIGH ${PCT}%] Run /compact before continuing. Switch to eco minimal to reduce growth." ;;
  70) MSG="[CTX ${PCT}%] Context approaching limit. Consider /compact soon." ;;
esac

# MSG is built from hardcoded literals + integer PCT — no quotes, backslashes,
# or control chars to escape. Bash printf is safe here. Avoids a python3 fork
# (~50-70ms cold-start per call). Verified by case statement above.
printf '{"systemMessage":"%s"}\n' "$MSG"
