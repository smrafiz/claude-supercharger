#!/usr/bin/env bash
# Claude Supercharger — Agent Gate
# Event: PreToolUse | Matcher: Agent
# Reads the stored agent classification. Warns on mismatch but allows
# explicit subagent dispatches — Claude may need different agents for subtasks.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
ROUTE_FILE="$SCOPE_DIR/.agent-route"

_INPUT=$(cat)
DISPATCHED=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
if [ -z "$DISPATCHED" ]; then
  DISPATCHED=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('subagent_type',''))" 2>/dev/null || echo "")
fi

[ -z "$DISPATCHED" ] && exit 0

# No classification stored — learn from first dispatch and latch
if [ ! -f "$ROUTE_FILE" ]; then
  echo "$DISPATCHED" > "$ROUTE_FILE"
  exit 0
fi

STORED_AGENT=$(cat "$ROUTE_FILE" 2>/dev/null || echo "")
[ -z "$STORED_AGENT" ] && exit 0

# Match on first word of stored agent name (case-insensitive)
FIRST_WORD=$(printf '%s\n' "$STORED_AGENT" | awk '{print tolower($1)}')
DISPATCHED_LOWER=$(printf '%s\n' "$DISPATCHED" | tr '[:upper:]' '[:lower:]')

if printf '%s\n' "$DISPATCHED_LOWER" | grep -qF "$FIRST_WORD"; then
  exit 0
fi

# Mismatch — warn but allow. The routing system message already guides Claude's
# primary agent choice. Blocking here prevents legitimate subtask dispatches
# (e.g., spawning a Critic for code review during a Writer-routed session).
echo "[Supercharger] Agent routing: session routed to '${STORED_AGENT}', dispatching '${DISPATCHED}'" >&2
exit 0
