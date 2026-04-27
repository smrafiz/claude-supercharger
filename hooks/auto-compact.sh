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
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "auto-compact" && exit 0

_INPUT=$(cat)

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
  rm -f "$HOME/.claude/supercharger/scope/.compact-last-band"
  exit 0
}

# ── Determine threshold band ──────────────────────────────────────────────────
if   [ "$PCT" -ge 90 ]; then BAND=90
elif [ "$PCT" -ge 80 ]; then BAND=80
else                          BAND=70
fi

# ── Debounce: skip if already warned at this band ────────────────────────────
STATE_FILE="$HOME/.claude/supercharger/scope/.compact-last-band"
LAST_BAND=$(cat "$STATE_FILE" 2>/dev/null || echo "0")

[ "$BAND" -le "$LAST_BAND" ] && exit 0

# ── Write new band state ──────────────────────────────────────────────────────
mkdir -p "$HOME/.claude/supercharger/scope"
printf '%s\n' "$BAND" > "$STATE_FILE"

# ── Compose message ───────────────────────────────────────────────────────────
case "$BAND" in
  90) MSG="[CTX CRITICAL ${PCT}%] Near context limit. Stop current task, run /compact, verify work is saved." ;;
  80) MSG="[CTX HIGH ${PCT}%] Run /compact before continuing. Switch to eco minimal to reduce growth." ;;
  70) MSG="[CTX ${PCT}%] Context approaching limit. Consider /compact soon." ;;
esac

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$MSG")
printf '{"systemMessage":%s}\n' "$MSG_JSON"
