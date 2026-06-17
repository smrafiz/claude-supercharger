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

# v2.6.38: one python3 fork replaces 3 jq (cwd, session_id, tool_name) +
# 1 python3 (message build) + 1 python3 (MSG_JSON wrap). Now: parse stdin,
# extract all fields, build tier-aware message, emit fields on stdout for bash
# to consume. Bash still owns the DENIED_FILE append + dedup check because
# those depend on lib-suppress state. ~60ms → ~40ms.
TIER="${SUPERCHARGER_TIER:-standard}"
PARSED=$(HOOK_INPUT="$_INPUT" TIER="$TIER" python3 <<'PYEOF' 2>/dev/null || true
import json, os, sys

raw = os.environ.get('HOOK_INPUT', '')
try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)

tool = (d.get('tool_name') or d.get('tool') or '').strip()
if not tool:
    sys.exit(0)

cwd = d.get('cwd') or ''
session_id = d.get('session_id') or ''
tier = os.environ.get('TIER', 'standard')

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

if tier == 'minimal':
    msg = f'[denied] {tool}' + (f': {summary[:50]}' if summary else '')
elif tier == 'lean':
    parts = [f'[Denied] {tool}']
    if summary:
        parts.append(summary)
    parts.append('do not retry')
    msg = ' — '.join(parts)
else:
    parts = [f'[Permission denied] User denied {tool}.']
    if summary:
        parts.append(f'Input: {summary}')
    parts.append('Do not retry this action. If you need to proceed, ask the user directly instead of re-attempting.')
    msg = ' | '.join(parts)

# Five lines for bash to sed-split: cwd, session_id, tool_name, raw msg (used
# as dedup key), JSON-encoded msg (used in final stdout). msg is single-line by
# construction (no newlines in any branch above), so line splitting is safe.
print(cwd)
print(session_id)
print(tool)
print(msg)
print(json.dumps(msg))
PYEOF
)

[ -z "$PARSED" ] && exit 0

PROJECT_DIR=$(printf '%s\n' "$PARSED" | sed -n '1p')
SESSION_ID=$(printf '%s\n' "$PARSED" | sed -n '2p')
TOOL_NAME=$(printf '%s\n' "$PARSED" | sed -n '3p')
MSG=$(printf '%s\n' "$PARSED" | sed -n '4p')
MSG_JSON=$(printf '%s\n' "$PARSED" | sed -n '5p')
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "permission-denied-advisor" && exit 0
hook_profile_skip "permission-denied-advisor" && exit 0

# Track denied tools for this session (so Claude can reference them)
if [ -n "$SESSION_ID" ] && [ -n "$TOOL_NAME" ]; then
  DENIED_FILE="$HOME/.claude/supercharger/scope/.denied-${SESSION_ID}"
  printf '%s\n' "$TOOL_NAME" >> "$DENIED_FILE" 2>/dev/null || true
fi

hook_already_emitted "permission-denied-advisor" "${SESSION_ID:-default}" "$MSG" && exit 0

printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
exit 0
