#!/usr/bin/env bash
# Claude Supercharger — SQL MCP Guard
# Event: PreToolUse | Matcher: mcp__postgres__*,mcp__supabase__*
#
# Blocks destructive SQL via the Postgres / Supabase MCP servers. Real incident:
# Supabase 2025 — Cursor agent with service-role MCP credentials processed an
# injected support ticket containing `DROP TABLE` + exfil SQL, executed against
# production. The official Postgres reference server is read-only but
# third-party forks (crystaldba/postgres-mcp etc.) allow writes.
#
# Denies destructive SQL verbs in the `query` (or equivalent) field. Allow
# SELECT/INSERT/UPDATE — those are the agent's legitimate workspace.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "mcp-sql-guard" && exit 0

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in
  mcp__postgres__*|mcp__supabase__*|mcp__mysql__*|mcp__sqlite__*) ;;
  *) exit 0 ;;
esac

# Extract query from common parameter names
QUERY=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.query // .tool_input.sql // .tool_input.statement // empty' 2>/dev/null || true)
[ -z "$QUERY" ] && exit 0

# Fast-path: skip if no destructive verb keyword anywhere
case "$QUERY" in
  *DROP*|*drop*|*TRUNCATE*|*truncate*|*DELETE*|*delete*|*ALTER*|*alter*|*GRANT*|*grant*|*REVOKE*|*revoke*) ;;
  *) exit 0 ;;
esac

# Word-boundary regex to avoid matching substrings like "alteration" or column
# names like "deleted_at". Case-insensitive.
QUERY_UPPER=$(printf '%s' "$QUERY" | tr '[:lower:]' '[:upper:]')

deny() {
  local verb="$1"
  local reason="destructive SQL verb '$verb' blocked — open a migration PR or run via psql with explicit user confirmation"
  echo "" >&2
  echo "Supercharger blocked SQL MCP call." >&2
  echo "  Tool   : $TOOL" >&2
  echo "  Verb   : $verb" >&2
  echo "  Query  : $(printf '%s' "$QUERY" | head -c 120)" >&2
  echo "" >&2
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# Use POSIX word boundaries via space/punctuation requirements
echo "$QUERY_UPPER" | grep -qE '(^|[^A-Z_])DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)' && deny "DROP"
echo "$QUERY_UPPER" | grep -qE '(^|[^A-Z_])TRUNCATE([[:space:]]+TABLE)?[[:space:]]+' && deny "TRUNCATE"
echo "$QUERY_UPPER" | grep -qE '(^|[^A-Z_])DELETE[[:space:]]+FROM[[:space:]]+' && deny "DELETE FROM"
echo "$QUERY_UPPER" | grep -qE '(^|[^A-Z_])ALTER[[:space:]]+(TABLE|DATABASE|SCHEMA)' && deny "ALTER"
echo "$QUERY_UPPER" | grep -qE '(^|[^A-Z_])GRANT[[:space:]]+' && deny "GRANT"
echo "$QUERY_UPPER" | grep -qE '(^|[^A-Z_])REVOKE[[:space:]]+' && deny "REVOKE"

exit 0
