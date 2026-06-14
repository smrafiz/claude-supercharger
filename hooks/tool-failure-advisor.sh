#!/usr/bin/env bash
# Claude Supercharger — Tool Failure Advisor
# Event: PostToolUseFailure | Matcher: (none)
# Injects failure context + tool-specific hints back to Claude when any tool errors.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "tool-failure-advisor" && exit 0
hook_profile_skip "tool-failure-advisor" && exit 0

MSG=$(printf '%s\n' "$_INPUT" | python3 -c "
import os, sys, json

TIER = os.environ.get('SUPERCHARGER_TIER', 'standard')

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = (d.get('tool_name') or '').strip()
error = (d.get('error') or d.get('message') or '').strip()
duration_ms = d.get('duration_ms')
inp = d.get('tool_input') or {}

if not tool or not error:
    sys.exit(0)

# Minimal: telegraphic — tool + truncated error only
if TIER == 'minimal':
    print(f'[fail] {tool}: {error[:60].replace(chr(10), chr(32))}')
    raise SystemExit(0)

error_short = error[:120].replace('\n', ' ')
parts = [f'[Tool failure] {tool} failed: {error_short}']

# Tool-specific hints
tool_lower = tool.lower()
err_lower = error.lower()

if tool_lower == 'bash':
    cmd = (inp.get('command') or '')[:80]
    if cmd:
        parts.append(f'Command: {cmd}')
    if 'permission denied' in err_lower:
        parts.append('Hint: check file permissions or use sudo if appropriate.')
    elif 'command not found' in err_lower:
        parts.append('Hint: tool may not be installed — check with which/brew/apt.')
    elif 'no such file' in err_lower:
        parts.append('Hint: verify path exists before running command.')

elif tool_lower == 'read':
    path = (inp.get('file_path') or '')
    if path:
        parts.append(f'Path: {path}')
    if 'no such file' in err_lower or 'not found' in err_lower:
        parts.append('Hint: use Glob to find the correct path before reading.')
    elif 'permission' in err_lower:
        parts.append('Hint: file exists but is not readable — check permissions.')

elif tool_lower in ('write', 'edit'):
    path = (inp.get('file_path') or '')
    if path:
        parts.append(f'Path: {path}')
    if 'no such file' in err_lower or 'directory' in err_lower:
        parts.append('Hint: parent directory may not exist — create it first.')
    elif 'permission' in err_lower:
        parts.append('Hint: file is not writable — check ownership.')

elif tool_lower == 'webfetch':
    url = (inp.get('url') or '')[:80]
    if url:
        parts.append(f'URL: {url}')
    if any(x in err_lower for x in ('timeout', 'timed out')):
        parts.append('Hint: request timed out — try again or use a different source.')
    elif any(x in err_lower for x in ('403', 'forbidden', '401', 'unauthorized')):
        parts.append('Hint: access denied — resource may require authentication.')
    elif any(x in err_lower for x in ('404', 'not found')):
        parts.append('Hint: URL not found — check the URL is correct and accessible.')

elif tool_lower == 'websearch':
    query = (inp.get('query') or '')[:80]
    if query:
        parts.append(f'Query: {query}')

if duration_ms is not None:
    try:
        ms = int(duration_ms)
        if ms > 5000:
            parts.append(f'Duration: {ms}ms (slow — consider a faster alternative).')
    except (ValueError, TypeError):
        pass

print(' | '.join(parts))
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "tool-failure-advisor" "$SESSION_ID" "$MSG" && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
