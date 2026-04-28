#!/usr/bin/env bash
# Claude Supercharger — Slow Tool Detector
# Event: PostToolUse | Matcher: (none)
# Warns Claude when a tool takes unusually long, with tool-specific thresholds.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "slow-tool-detector" && exit 0
hook_profile_skip "slow-tool-detector" && exit 0

MSG=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

duration_ms = d.get('duration_ms')
if duration_ms is None:
    sys.exit(0)

try:
    ms = int(duration_ms)
except (ValueError, TypeError):
    sys.exit(0)

tool = (d.get('tool_name') or '').strip().lower()
inp = d.get('tool_input') or {}

# Per-tool thresholds (ms)
thresholds = {
    'bash':      10_000,
    'webfetch':   8_000,
    'websearch':  8_000,
    'read':       3_000,
    'write':      3_000,
    'edit':       3_000,
    'glob':       5_000,
    'grep':       5_000,
}
threshold = thresholds.get(tool, 10_000)

if ms < threshold:
    sys.exit(0)

secs = ms / 1000
hint = ''
if tool == 'bash':
    cmd = (inp.get('command') or '')[:80]
    hint = f'Command: {cmd}' if cmd else ''
    suggestion = 'Consider breaking into smaller commands or running async.'
elif tool in ('webfetch', 'websearch'):
    url = (inp.get('url') or inp.get('query') or '')[:80]
    hint = f'Target: {url}' if url else ''
    suggestion = 'Network may be slow — consider retrying or using a cached source.'
elif tool in ('read', 'write', 'edit'):
    path = (inp.get('file_path') or '')[:80]
    hint = f'Path: {path}' if path else ''
    suggestion = 'File may be large — consider reading specific line ranges.'
elif tool in ('glob', 'grep'):
    suggestion = 'Search scope may be too broad — narrow the pattern or path.'
else:
    suggestion = 'Consider a faster alternative.'

parts = [f'[Slow tool] {d.get(\"tool_name\", tool)} took {secs:.1f}s (threshold: {threshold/1000:.0f}s).']
if hint:
    parts.append(hint)
parts.append(suggestion)
print(' | '.join(parts))
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
