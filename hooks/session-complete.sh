#!/usr/bin/env bash
# Claude Supercharger — Session Complete Hook
# Event: Stop | Matcher: (none)
# Logs session metadata on exit. Sends webhook if configured.

set -euo pipefail

SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"
SUPERCHARGER_DIR="$HOME/.claude/supercharger"

mkdir -p "$SUMMARIES_DIR" 2>/dev/null || true

# Parse cost from Stop event stdin (graceful fallback if not present)
INPUT=$(cat)
COST=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    cost = (d.get('cost_usd')
            or d.get('total_cost_usd')
            or (d.get('cost') or {}).get('total_cost_usd')
            or 0)
    print(f'{float(cost):.4f}')
except Exception:
    print('0')
" 2>/dev/null || echo "0")

# Detect active economy tier from installed rules
ECONOMY="lean"
if [ -f "$HOME/.claude/rules/economy.md" ]; then
  if grep -q "Active Tier: Minimal" "$HOME/.claude/rules/economy.md" 2>/dev/null; then
    ECONOMY="minimal"
  elif grep -q "Active Tier: Standard" "$HOME/.claude/rules/economy.md" 2>/dev/null; then
    ECONOMY="standard"
  fi
fi

# Persist cost + economy for next session's feedback injection
COST_FILE="$SUPERCHARGER_DIR/.last-session-cost"
{
  echo "cost=$COST"
  echo "economy=$ECONOMY"
  echo "timestamp=$(date +%Y-%m-%dT%H:%M:%S)"
} > "$COST_FILE" 2>/dev/null || true

# Capture session metadata
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
MODIFIED=$(git diff --name-only HEAD 2>/dev/null | head -10 || echo "")

# Write session-end marker to summaries dir
MARKER_FILE="$SUMMARIES_DIR/.last-session"
{
  echo "timestamp: $TIMESTAMP"
  echo "project: $PROJECT"
  echo "branch: $BRANCH"
  echo "modified_files:"
  if [ -n "$MODIFIED" ]; then
    echo "$MODIFIED" | while read -r f; do echo "  - $f"; done
  else
    echo "  (none detected)"
  fi
} > "$MARKER_FILE" 2>/dev/null || true

# Send webhook notification if configured — uses shared webhook lib
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  if webhook_enabled; then
    send_webhook "Claude Code session complete" || true
  fi
fi

exit 0
