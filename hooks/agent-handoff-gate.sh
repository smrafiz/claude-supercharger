#!/usr/bin/env bash
# Claude Supercharger — Agent Handoff Gate
# Event: SubagentStop | Matcher: (none)
# Validates sub-agent output quality before the result flows back to the parent.
# Injects a warning if the output shows signs of incomplete or failed work.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# Extract agent output text
AGENT_OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # agent result may be in result, output, or content
    out = d.get('result') or d.get('output') or ''
    if isinstance(out, list):
        out = ' '.join(str(x.get('text','') if isinstance(x,dict) else x) for x in out)
    print(str(out)[:4000])
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$AGENT_OUTPUT" ] && exit 0

AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")

# Score output quality — look for failure signals
QUALITY_ISSUE=$(python3 -c "
import re, sys

output = sys.argv[1].lower()

# Incomplete work signals
incomplete = [
    r'\btodo\b', r'\bfixme\b', r'\bnot implemented\b', r'\bstub\b',
    r'\bpass\s*#', r'\b\.\.\.\s*$', r'placeholder',
    r'i (was unable|could not|cannot|am unable) to',
    r'(failed|error|exception) (to|while|when)',
    r'\bleft as an exercise\b',
]
# Uncertainty signals that should trigger a check
uncertain = [
    r'i (think|believe|assume) (this|it) (should|might|may|could)',
    r'(should|might) work', r'(probably|likely) (correct|fine|ok)',
    r'i (haven.t|have not) (tested|verified|confirmed)',
]

for pattern in incomplete:
    if re.search(pattern, output):
        print('incomplete')
        sys.exit(0)

count = sum(1 for p in uncertain if re.search(p, output))
if count >= 2:
    print('unverified')
    sys.exit(0)

print('')
" "$AGENT_OUTPUT" 2>/dev/null || echo "")

[ -z "$QUALITY_ISSUE" ] && exit 0

if [ "$QUALITY_ISSUE" = "incomplete" ]; then
  MSG="[AGENT-GATE] Sub-agent output contains incomplete work signals (TODO, stub, unimplemented, or explicit failure). Verify the result before proceeding — do not silently accept partial output."
else
  MSG="[AGENT-GATE] Sub-agent output contains multiple unverified claims (\"should work\", \"probably correct\", \"haven't tested\"). Treat this output with skepticism and verify key assertions before continuing."
fi

echo "[Supercharger] agent-handoff-gate: quality issue detected (${QUALITY_ISSUE}) for agent=${AGENT_ID}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null) || exit 0

if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
