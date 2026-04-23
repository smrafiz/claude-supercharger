#!/usr/bin/env bash
# Claude Supercharger — Adaptive Economy
# Event: UserPromptSubmit | Matcher: (none)
# Auto-switches economy tier based on context window usage.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "adaptive-economy" && exit 0

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

# --- Opt-out check ---
if [ "${SUPERCHARGER_NO_AUTO_ECONOMY:-}" = "1" ]; then
  exit 0
fi

# Check .supercharger.json autoEconomy: false
if [ -f "$PROJECT_DIR/.supercharger.json" ]; then
  AUTO_OK=$(python3 -c "
import json, sys
try:
  d = json.load(open('$PROJECT_DIR/.supercharger.json'))
  print('false' if d.get('autoEconomy') is False else 'true')
except Exception:
  print('true')
" 2>/dev/null || echo "true")
  if [ "$AUTO_OK" = "false" ]; then
    exit 0
  fi
fi

# --- Auto-switch logic ---
MSG=""
NEW_TIER=""

if [ "$PCT" -ge 80 ] && [ "$TIER" = "lean" ]; then
  NEW_TIER="minimal"
  MSG="[ECO] Auto-switched to Minimal (context at ${PCT}%)"
elif [ "$PCT" -ge 70 ] && [ "$TIER" = "standard" ]; then
  NEW_TIER="lean"
  MSG="[ECO] Auto-switched to Lean (context at ${PCT}%)"
elif [ "$PCT" -lt 30 ] && [ "$TIER" = "minimal" ]; then
  MSG="[ECO] Context low (${PCT}%). Lean tier OK if you want richer output."
elif [ "$PCT" -lt 20 ] && [ "$TIER" = "lean" ]; then
  MSG="[ECO] Context low. Standard tier OK."
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

# Perform auto-switch if applicable
if [ -n "$NEW_TIER" ]; then
  mkdir -p "$SCOPE_DIR"
  echo "$NEW_TIER" > "$ECONOMY_TIER_FILE"

  # Append to session history, keep last 20 entries
  HISTORY_FILE="$SCOPE_DIR/.economy-history.jsonl"
  ENTRY="{\"date\":\"$(date +%Y-%m-%d)\",\"tier_before\":\"${TIER}\",\"tier_after\":\"${NEW_TIER}\",\"context_pct\":${PCT}}"
  echo "$ENTRY" >> "$HISTORY_FILE"
  # Trim to last 20 lines
  if [ "$(wc -l < "$HISTORY_FILE")" -gt 20 ]; then
    tail -20 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
  fi
fi

echo "[Supercharger] adaptive-economy: ${PCT}% tier=${TIER}${NEW_TIER:+ -> $NEW_TIER}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
