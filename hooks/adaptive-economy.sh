#!/usr/bin/env bash
# Claude Supercharger — Adaptive Economy
# Event: UserPromptSubmit | Matcher: (none)
# Auto-suggests economy tier changes based on context window usage.

set -euo pipefail

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
if [ "$PCT" -ge 80 ] && [ "$TIER" != "minimal" ]; then
  MSG="[ECONOMY] Context at ${PCT}%. Suggest switching to minimal tier to conserve tokens. Tell user: 'Context is high — recommend running: eco minimal'"
elif [ "$PCT" -ge 60 ] && [ "$TIER" = "standard" ]; then
  MSG="[ECONOMY] Context at ${PCT}%. Suggest switching to lean tier. Tell user: 'Consider running: eco lean'"
elif [ "$PCT" -lt 30 ] && [ "$TIER" = "minimal" ]; then
  MSG="[ECONOMY] Context low at ${PCT}%. User could switch to a more detailed tier if needed: eco lean or eco standard"
fi

echo "[Supercharger] adaptive-economy: ${PCT}% context, current=${TIER}, suggestion=${MSG:-none}" >&2

[ -z "$MSG" ] && exit 0

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
