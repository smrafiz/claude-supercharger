#!/usr/bin/env bash
# Claude Supercharger — Agent Gate
# Event: PreToolUse | Matcher: Agent
# Reads the stored agent classification and blocks dispatch of any other agent.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
ROUTE_FILE="$SCOPE_DIR/.agent-route"

DISPATCHED=$(python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('subagent_type', ''))
except:
    print('')
" 2>/dev/null || echo "")

[ -z "$DISPATCHED" ] && exit 0

# No classification stored — learn from first dispatch and latch
if [ ! -f "$ROUTE_FILE" ]; then
  echo "$DISPATCHED" > "$ROUTE_FILE"
  exit 0
fi

STORED_AGENT=$(cat "$ROUTE_FILE" 2>/dev/null || echo "")
[ -z "$STORED_AGENT" ] && exit 0

# Match on first word of stored agent name (case-insensitive)
# "Sherlock Holmes (Detective)" → check if "sherlock" appears in dispatched (lowercased)
FIRST_WORD=$(printf '%s\n' "$STORED_AGENT" | awk '{print tolower($1)}')
DISPATCHED_LOWER=$(echo "$DISPATCHED" | tr '[:upper:]' '[:lower:]')

if printf '%s\n' "$DISPATCHED_LOWER" | grep -qF "$FIRST_WORD"; then
  exit 0
fi

echo "[Supercharger] Agent routing: dispatch '${STORED_AGENT}' for this task (not '${DISPATCHED}')" >&2
exit 2
