#!/usr/bin/env bash
# Claude Supercharger — Session End Hook
# Event: SessionEnd | Matcher: (none)
# Logs session stats and cleans up transient scope files.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
LOGS_DIR="$SUPERCHARGER_DIR/logs"
mkdir -p "$LOGS_DIR" 2>/dev/null || true

# Parse reason and session_id from stdin
_INPUT=$(cat)
REASON=$(printf '%s\n' "$_INPUT" | jq -r '.reason // empty' 2>/dev/null || true)
if [ -z "$REASON" ]; then
  REASON=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('reason','unknown'))" 2>/dev/null || echo "unknown")
fi
[ -z "$REASON" ] && REASON="unknown"

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# Read transient scope stats
AGENT="none"
[ -f "$SCOPE_DIR/.agent-dispatched-${SESSION_ID}" ] && AGENT=$(cat "$SCOPE_DIR/.agent-dispatched-${SESSION_ID}" 2>/dev/null || echo "none")
[ "$AGENT" = "none" ] && [ -f "$SCOPE_DIR/.agent-classified-${SESSION_ID}" ] && AGENT=$(cat "$SCOPE_DIR/.agent-classified-${SESSION_ID}" 2>/dev/null || echo "none")

COST="none"
[ -f "$SCOPE_DIR/.prompt-cost-${SESSION_ID}" ] && COST=$(cat "$SCOPE_DIR/.prompt-cost-${SESSION_ID}" 2>/dev/null || echo "none")

# Log session end
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] Session ended: reason=$REASON agent=$AGENT cost=$COST" >> "$LOGS_DIR/sessions.log" 2>/dev/null || true

# Clean up transient scope files for this session
rm -f \
  "$SCOPE_DIR/.prompt-cost-${SESSION_ID}" \
  "$SCOPE_DIR/.prompt-tokens-${SESSION_ID}" \
  "$SCOPE_DIR/.last-prompt-tokens-${SESSION_ID}" \
  "$SCOPE_DIR/.agent-classified-${SESSION_ID}" \
  "$SCOPE_DIR/.agent-dispatched-${SESSION_ID}" \
  "$SCOPE_DIR/.active-mcp-${SESSION_ID}" \
  "$SCOPE_DIR/.denied-${SESSION_ID}" \
  "$SCOPE_DIR/.keep-going-${SESSION_ID}" \
  "$SCOPE_DIR"/.dedup-${SESSION_ID}-* \
  2>/dev/null || true

# Periodic global cleanup (TTL-based) — at most once per day
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" 2>/dev/null && pwd)"
if [ -z "$TOOLS_DIR" ] || [ ! -x "$TOOLS_DIR/scope-cleanup.sh" ]; then
  TOOLS_DIR="$HOME/.claude/supercharger/tools"
fi
LAST_CLEAN_FILE="$SCOPE_DIR/.last-cleanup"
NOW=$(date +%s)
LAST_CLEAN=0
[ -f "$LAST_CLEAN_FILE" ] && LAST_CLEAN=$(cat "$LAST_CLEAN_FILE" 2>/dev/null || echo 0)
if [ $((NOW - LAST_CLEAN)) -gt 86400 ] && [ -x "$TOOLS_DIR/scope-cleanup.sh" ]; then
  bash "$TOOLS_DIR/scope-cleanup.sh" --apply >/dev/null 2>&1 &
  echo "$NOW" > "$LAST_CLEAN_FILE" 2>/dev/null || true
fi

echo "[Supercharger] session-end: cleaned up (reason=$REASON)" >&2

exit 0
