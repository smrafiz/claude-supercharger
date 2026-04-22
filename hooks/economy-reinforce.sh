#!/usr/bin/env bash
# Claude Supercharger — Economy Tier Reinforcement
# Event: UserPromptSubmit | Matcher: (none)
# Re-injects active economy tier rules every Nth prompt to prevent drift.
# Models lose tier instructions after context compression or long conversations.
# Adapted from caveman per-turn reinforcement pattern.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# Resolve current tier
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

# Standard tier is verbose by default — no reinforcement needed
[ "$TIER" = "standard" ] && exit 0

# Emit every 3rd prompt to balance drift prevention vs noise.
# First prompt gets rules from SessionStart; this catches post-compaction drift.
COUNTER_FILE="$SCOPE_DIR/.eco-reinforce-counter"
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=${COUNT%%.*}
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 3)) -ne 0 ] && exit 0

# Build tier-specific reinforcement message
case "$TIER" in
  minimal)
    MSG="[ECONOMY:MINIMAL] Telegraphic. Bare deliverables. No ceremony/filler/restatement. Fragments OK. Code blocks only. OVERRIDE: use full clarity for security warnings + irreversible actions."
    ;;
  lean)
    MSG="[ECONOMY:LEAN] Concise. Lead with deliverable. No ceremony. Bullets over prose. OVERRIDE: use full clarity for security warnings + irreversible actions."
    ;;
  *)
    exit 0
    ;;
esac

echo "[Supercharger] economy-reinforce: tier=${TIER} count=${COUNT}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
