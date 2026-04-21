#!/usr/bin/env bash
# Claude Supercharger — Adaptive Economy
# Event: UserPromptSubmit | Matcher: (none)
# Auto-suggests economy tier changes based on context window usage.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"

_INPUT=$(cat)

PCT=$(printf '%s\n' "$_INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
if [ -z "$PCT" ]; then
  PCT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
pct = data.get('context_window', {}).get('used_percentage', '')
print(int(pct) if pct != '' else '')
" 2>/dev/null || echo "")
fi

[ -z "$PCT" ] && exit 0

PCT=${PCT%%.*}

TIER=""
ECONOMY_TIER_FILE="$SCOPE_DIR/.economy-tier"
if [ -f "$ECONOMY_TIER_FILE" ]; then
  TIER=$(cat "$ECONOMY_TIER_FILE" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
fi
if [ -z "$TIER" ]; then
  ECONOMY_MD="$HOME/.claude/rules/economy.md"
  if [ -f "$ECONOMY_MD" ]; then
    TIER=$(grep -m1 '^### Active Tier:' "$ECONOMY_MD" 2>/dev/null | sed 's/^### Active Tier:[[:space:]]*//' | sed 's/[[:space:]].*//' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  fi
fi
[ -z "$TIER" ] && TIER="lean"

MSG=""
# PCT>=70: context-advisor already fires — only add tier suggestion if not minimal
if [ "$PCT" -ge 70 ] && [ "$TIER" != "minimal" ]; then
  MSG="[ECO] →eco minimal"
elif [ "$PCT" -ge 60 ] && [ "$TIER" = "standard" ]; then
  MSG="[ECO] ${PCT}%→eco lean"
elif [ "$PCT" -lt 30 ] && [ "$TIER" = "minimal" ]; then
  MSG="[ECO] ${PCT}% low→eco lean ok"
fi

[ -z "$MSG" ] && exit 0

# Dedup: bucket PCT to nearest 10 to avoid re-injection on every prompt
PCT_BUCKET=$(( PCT / 10 * 10 ))
DEDUP_KEY="${PCT_BUCKET}:${TIER}"
DEDUP_FILE="$SCOPE_DIR/.eco-last"
LAST_KEY=$(cat "$DEDUP_FILE" 2>/dev/null || echo "")
if [ "$DEDUP_KEY" = "$LAST_KEY" ]; then
  exit 0
fi
echo "$DEDUP_KEY" > "$DEDUP_FILE"

echo "[Supercharger] adaptive-economy: ${PCT}% tier=${TIER}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
