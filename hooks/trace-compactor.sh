#!/usr/bin/env bash
# Claude Supercharger — Trace Compactor Hook
# Event: PostToolUse | Matcher: Bash
# Compresses large Python/Node tracebacks before Claude processes them.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

OUTPUT=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null || true)
if [ -z "$OUTPUT" ]; then
  OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; r=json.load(sys.stdin).get('tool_response',{}); print(r.get('stdout') or r.get('output') or '')" 2>/dev/null || echo "")
fi

[ -z "$OUTPUT" ] && exit 0

# Skip python startup cost for short outputs
[ "${#OUTPUT}" -lt 2000 ] && exit 0

TC_OUTPUT="$OUTPUT" TC_SUPPRESS="$HOOK_SUPPRESS" python3 <<'PYEOF'
import os, json, re

output = os.environ.get('TC_OUTPUT', '')
original_len = len(output)

summary = None

# --- Python traceback ---
if 'Traceback (most recent call last):' in output:
    lines = output.splitlines()
    # Count frames (lines starting with '  File \"')
    file_lines = [l for l in lines if re.match(r'\s+File \"', l)]
    frame_count = len(file_lines)
    # Innermost frame = last File line + next line (code snippet), capture just the File line
    innermost = file_lines[-1].strip() if file_lines else 'unknown'
    # Extract file:line from innermost frame
    m = re.match(r'File \"(.+?)\", line (\d+)', innermost)
    if m:
        at_loc = f'{m.group(1)}:{m.group(2)}'
    else:
        at_loc = innermost
    # Exception type + message = last non-empty line
    last_line = ''
    for l in reversed(lines):
        if l.strip():
            last_line = l.strip()
            break
    # Split on first colon for type vs message
    exc_match = re.match(r'^(\w+(?:Error|Exception|Warning))\s*:(.*)', last_line)
    if exc_match:
        exc_type = exc_match.group(1)
        exc_msg = exc_match.group(2).strip()
    else:
        # Try splitting on first colon anyway
        parts = last_line.split(':', 1)
        exc_type = parts[0].strip()
        exc_msg = parts[1].strip() if len(parts) > 1 else ''
    summary = f'[TRACEBACK COMPACTED: {frame_count} frames → {exc_type}: {exc_msg} (at {at_loc})]'

# --- Node.js error stack ---
elif re.search(r'\bat (?:Object\.|async |new |Module\.)', output):
    lines = output.splitlines()
    # Error message: first non-empty line
    error_msg = ''
    stack_frames = []
    for i, l in enumerate(lines):
        stripped = l.strip()
        if not error_msg and stripped:
            error_msg = stripped
        elif re.match(r'\s+at ', l):
            stack_frames.append(stripped)
        if len(stack_frames) >= 3:
            break
    top_frames = '; '.join(stack_frames[:3]) if stack_frames else 'unknown'
    # Truncate error_msg if very long
    if len(error_msg) > 120:
        error_msg = error_msg[:117] + '...'
    summary = f'[NODE STACK COMPACTED: {error_msg} | top frames: {top_frames}]'

# --- Generic large output truncation ---
else:
    first = output[:2000]
    last = output[-500:]
    omitted = original_len - 2500
    summary = first + f'\n[... {omitted} chars omitted ...]\n' + last

new_len = len(summary)
# v2.6.2: replace Claude's view of the tool output with the compacted summary
# via hookSpecificOutput.updatedToolOutput. Previously this hook emitted a
# systemMessage which added the summary AS WELL as Claude seeing the full
# traceback — defeating the purpose. updatedToolOutput cleanly substitutes.
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'updatedToolOutput': summary,
    }
}))
import sys
sys.stderr.write(f'[Supercharger] trace-compactor: compacted {original_len} → {new_len} chars\n')
PYEOF

exit 0
