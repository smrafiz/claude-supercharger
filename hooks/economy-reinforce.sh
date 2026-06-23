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
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
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

# Fire only after compaction (post-compact-inject writes .memory-restored).
# First prompt gets tier rules from SessionStart; we only re-inject when
# compaction may have dropped them. Track own ack flag so we fire at most
# once per compaction event without consuming the shared statusline flag.
RESTORED_FLAG="$SCOPE_DIR/.memory-restored"
ECO_ACK_FLAG="$SCOPE_DIR/.eco-reinforce-acked"
[ ! -f "$RESTORED_FLAG" ] && exit 0
RESTORED_MTIME=$(stat -c '%Y' "$RESTORED_FLAG" 2>/dev/null || stat -f '%m' "$RESTORED_FLAG" 2>/dev/null || echo "")
case "$RESTORED_MTIME" in ''|*[!0-9]*) RESTORED_MTIME=0 ;; esac
ACK_MTIME=0
if [ -f "$ECO_ACK_FLAG" ]; then
  ACK_MTIME=$(stat -c '%Y' "$ECO_ACK_FLAG" 2>/dev/null || stat -f '%m' "$ECO_ACK_FLAG" 2>/dev/null || echo "")
  case "$ACK_MTIME" in ''|*[!0-9]*) ACK_MTIME=0 ;; esac
fi
[ "$RESTORED_MTIME" -le "$ACK_MTIME" ] && exit 0
touch "$ECO_ACK_FLAG" 2>/dev/null || true

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

echo "[Supercharger] economy-reinforce: tier=${TIER}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
