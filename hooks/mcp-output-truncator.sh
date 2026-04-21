#!/usr/bin/env bash
# Claude Supercharger — MCP Output Truncator
# Event: PostToolUse | Matcher: mcp__
# Truncates large MCP tool responses to prevent context window flooding.
# GitHub issue #29971: MCP responses can waste 25K+ tokens per heavy tool call.

set -euo pipefail

INPUT=$(cat)

# Extract tool response output
OUTPUT=$(printf '%s\n' "$INPUT" | jq -r '.tool_response.output // empty' 2>/dev/null)
if [ -z "$OUTPUT" ]; then
  OUTPUT=$(printf '%s\n' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_response',{}).get('output',''))" 2>/dev/null || echo "")
fi

[ -z "$OUTPUT" ] && exit 0

# Skip short responses — no truncation needed
[ "${#OUTPUT}" -lt 3000 ] && exit 0

TOOL_NAME=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

MCP_OUTPUT="$OUTPUT" MCP_TOOL="$TOOL_NAME" python3 <<'PYEOF'
import os, json, sys

output = os.environ.get('MCP_OUTPUT', '')
tool = os.environ.get('MCP_TOOL', 'mcp')
original_len = len(output)

MAX_HEAD = 3000
MAX_TAIL = 500
MAX_TOTAL = MAX_HEAD + MAX_TAIL

if original_len <= MAX_TOTAL:
    sys.exit(0)

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

print(json.dumps({
    'systemMessage': summary, 'suppressOutput': True
}))
PYEOF

exit 0
