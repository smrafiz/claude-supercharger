#!/usr/bin/env bash
# Claude Supercharger — MCP Output Truncator
# Event: PostToolUse | Matcher: mcp__
# Truncates large MCP tool responses to prevent context window flooding.
# GitHub issue #29971: MCP responses can waste 25K+ tokens per heavy tool call.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)

# v2.6.37: bash fast-path. If the entire payload is shorter than 3500 bytes,
# the embedded output can't reach the 3000-char truncation threshold. Skip all
# forks (jq, python3) and exit immediately. This is the common case — most MCP
# responses are short.
if [ "${#_INPUT}" -lt 3500 ]; then
  exit 0
fi

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.37: one python3 fork replaces 2 jq (output, tool_name) + 1 python3
# fallback + 1 python3 main. Now: parse stdin once, extract output + tool_name,
# length-check, build summary, emit JSON.
MCP_INPUT="$_INPUT" MCP_SUPPRESS="$HOOK_SUPPRESS" python3 <<'PYEOF' 2>/dev/null
import os, json, sys

raw = os.environ.get('MCP_INPUT', '')
try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)

output = (d.get('tool_response') or {}).get('output') or ''
if not isinstance(output, str):
    sys.exit(0)
original_len = len(output)

MAX_HEAD = 3000
MAX_TAIL = 500
MAX_TOTAL = MAX_HEAD + MAX_TAIL
if original_len <= MAX_TOTAL:
    sys.exit(0)

tool = d.get('tool_name') or 'mcp'

def describe_value(v, depth=0):
    if isinstance(v, dict):
        if depth > 0:
            return '{' + ', '.join(f'{k}: ...' for k in list(v.keys())[:4]) + (', ...' if len(v) > 4 else '') + '}'
        return '{' + str(len(v)) + ' keys}'
    if isinstance(v, list):
        return f'[{len(v)} items]'
    s = str(v)
    return s[:80] + ('...' if len(s) > 80 else '')

# Try structure-aware JSON summary
summary = None
try:
    data = json.loads(output)
    lines = [f'[MCP:{tool} {original_len}chars — structure summary]']
    if isinstance(data, dict):
        for k, v in list(data.items())[:12]:
            lines.append(f'  {k}: {describe_value(v, depth=1)}')
        if len(data) > 12:
            lines.append(f'  ... ({len(data) - 12} more keys)')
    elif isinstance(data, list):
        lines.append(f'  [{len(data)} items]')
        for item in data[:3]:
            lines.append(f'  - {describe_value(item, depth=1)}')
        if len(data) > 3:
            lines.append(f'  ... ({len(data) - 3} more)')
    else:
        raise ValueError('scalar')
    summary = '\n'.join(lines)
except Exception:
    pass

if summary is None:
    head = output[:MAX_HEAD]
    tail = output[-MAX_TAIL:]
    omitted = original_len - MAX_TOTAL
    summary = head + f'\n[... {omitted} chars truncated ...]\n' + tail

sys.stderr.write(f'[Supercharger] mcp-output-truncator: {tool} {original_len} → {len(summary)} chars\n')

# v2.6.2: updatedToolOutput replaces what Claude sees, vs systemMessage which
# stacks on top of the original. Original stays in the transcript log.
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'updatedToolOutput': summary,
    }
}))
PYEOF

exit 0
