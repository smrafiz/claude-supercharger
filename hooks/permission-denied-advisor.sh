#!/usr/bin/env bash
# Claude Supercharger — Permission Denied Advisor
# Event: PermissionDenied | Matcher: (none)
# Injects context when user denies a permission, so Claude stops retrying
# and understands the user's intent.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "permission-denied-advisor" && exit 0
hook_profile_skip "permission-denied-advisor" && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

MSG=$(printf '%s\n' "$_INPUT" | python3 -c "
import os, sys, json

TIER = os.environ.get('SUPERCHARGER_TIER', 'standard')

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = (d.get('tool_name') or d.get('tool') or '').strip()
if not tool:
    sys.exit(0)

inp = d.get('tool_input') or {}

summary = ''
if inp.get('command'):
    summary = inp['command'][:80]
elif inp.get('file_path'):
    summary = inp['file_path'][:80]
elif inp.get('url'):
    summary = inp['url'][:80]
elif isinstance(inp, dict) and inp:
    summary = str(inp)[:60]

if TIER == 'minimal':
    print(f'[denied] {tool}{(\": \" + summary[:50]) if summary else \"\"}')
elif TIER == 'lean':
    parts = [f'[Denied] {tool}']
    if summary:
        parts.append(summary)
    parts.append('do not retry')
    print(' — '.join(parts))
else:
    parts = [f'[Permission denied] User denied {tool}.']
    if summary:
        parts.append(f'Input: {summary}')
    parts.append('Do not retry this action. If you need to proceed, ask the user directly instead of re-attempting.')
    print(' | '.join(parts))
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

# Track denied tools for this session (so Claude can reference them)
if [ -n "$SESSION_ID" ] && [ -n "$TOOL_NAME" ]; then
  DENIED_FILE="$HOME/.claude/supercharger/scope/.denied-${SESSION_ID}"
  printf '%s\n' "$TOOL_NAME" >> "$DENIED_FILE" 2>/dev/null || true
fi

hook_already_emitted "permission-denied-advisor" "${SESSION_ID:-default}" "$MSG" && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
