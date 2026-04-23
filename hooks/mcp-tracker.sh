#!/usr/bin/env bash
# Claude Supercharger — MCP Tracker
# Event: PostToolUse | Matcher: mcp__
# Writes the active MCP server name to a scope file for statusline display.

set -euo pipefail

_INPUT=$(cat)
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ -z "$TOOL_NAME" ]; then
  TOOL_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
fi

[ -z "$TOOL_NAME" ] && exit 0
case "${SUPERCHARGER_PROFILE:-standard}" in minimal|fast) exit 0 ;; esac

# Extract MCP server name from tool_name (format: mcp__servername__toolname)
if [[ "$TOOL_NAME" =~ ^mcp__([^_]+) ]]; then
  MCP_NAME="${BASH_REMATCH[1]}"
  SCOPE_DIR="$HOME/.claude/supercharger/scope"
  mkdir -p "$SCOPE_DIR" 2>/dev/null || true
  echo "$MCP_NAME" > "$SCOPE_DIR/.active-mcp-${SESSION_ID}"
fi

exit 0
