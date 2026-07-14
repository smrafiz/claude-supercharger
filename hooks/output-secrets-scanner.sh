#!/usr/bin/env bash
# Claude Supercharger — Output Secrets Scanner Hook
# Event: PostToolUse | Matcher: Bash,Read
# Scans tool output for leaked secrets and warns Claude not to repeat them.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.77: Bash PostToolUse payloads deliver output under `.tool_response.stdout`,
# not `.tool_response.output`. Reading only `.output` made this hook inert for
# every Bash tool call — secrets in `cat ~/.env`, `env`, `printenv` output were
# never scanned. Read both fields, prefer stdout (Bash) then output (Read tool).
OUTPUT=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null || true)
if [ -z "$OUTPUT" ]; then
  # v2.9.17: MCP responses carry text under content[]/other shapes, not stdout —
  # for mcp__ tools, stringify the whole tool_response so secrets in an MCP reply
  # are scanned too. Bash/Read behavior is unchanged (still stdout/output).
  OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('tool_response')
tool = str(d.get('tool_name') or '')
if isinstance(r, dict):
    out = r.get('stdout') or r.get('output') or ''
    if not out and tool.startswith('mcp__'):
        out = json.dumps(r)
    print(out)
elif r is not None and tool.startswith('mcp__'):
    print(json.dumps(r))
" 2>/dev/null || echo "")
fi

[ -z "$OUTPUT" ] && exit 0
[ "${#OUTPUT}" -lt 10 ] && exit 0

# v2.9.8: SECRET_PATTERNS moved to lib-secret-patterns.sh — the single source of
# truth shared with commit-secret-guard.sh (prevents cross-channel parity drift).
# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh"

COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$OUTPUT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  echo "[Supercharger] output-secrets-scanner: SECRET DETECTED in tool output — warning Claude" >&2
  MSG='[SECURITY] Tool output contains what appears to be a secret/credential. Do NOT repeat, log, or include this value in your response. Refer to it generically (e.g., "the API key") without showing the actual value.'
  MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
  # Signal statusline: scan alert (per-session, not global — v2.6.49)
  SCOPE_DIR="$SUPERCHARGER_STATE/scope"
  SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -z "$SID" ] && SID="default"
  mkdir -p "$SCOPE_DIR"
  echo "secrets" > "$SCOPE_DIR/.scan-alert-${SID}" 2>/dev/null || true
  exit 2
fi

exit 0
