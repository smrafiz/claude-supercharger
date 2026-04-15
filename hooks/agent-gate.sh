#!/usr/bin/env bash
# Claude Supercharger — Agent Gate
# Event: PreToolUse | Matcher: Agent
# Reads the stored agent classification. Warns on mismatch but allows
# explicit subagent dispatches — Claude may need different agents for subtasks.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"

_INPUT=$(cat)
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

CLASSIFIED_FILE="$SCOPE_DIR/.agent-classified-${SESSION_ID}"
DISPATCHED_FILE="$SCOPE_DIR/.agent-dispatched-${SESSION_ID}"

# Try multiple fields where the agent name might be
DISPATCHED=$(printf '%s\n' "$_INPUT" | jq -r '
  .tool_input.subagent_type //
  .tool_input.agent //
  .tool_input.name //
  .tool_input.description //
  empty
' 2>/dev/null)

# Fallback: extract agent name from the description field (first line, first few words)
if [ -z "$DISPATCHED" ]; then
  DISPATCHED=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
ti = json.load(sys.stdin).get('tool_input', {})
print(ti.get('subagent_type', '') or ti.get('agent', '') or ti.get('name', '') or ti.get('description', '').split('\n')[0][:60])
" 2>/dev/null || echo "")
fi

[ -z "$DISPATCHED" ] && exit 0

# Clean up: if description is long, take first meaningful chunk
if [ ${#DISPATCHED} -gt 60 ]; then
  DISPATCHED="${DISPATCHED:0:57}..."
fi

# Read classifier's route for mismatch detection
STORED_AGENT=$(cat "$CLASSIFIED_FILE" 2>/dev/null || echo "")

# Write dispatched agent separately — statusline reads this, not .agent-classified
mkdir -p "$SCOPE_DIR"
echo "$DISPATCHED" > "$DISPATCHED_FILE"

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
