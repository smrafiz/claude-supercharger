#!/usr/bin/env bash
# Claude Supercharger — Bash Output Compactor
# Event: PostToolUse | Matcher: Bash
# Compresses verbose Bash output (git log, pytest/vitest/jest, npm install)
# before it enters Claude's context. Uses updatedToolOutput (v2.1.121 schema)
# to replace what Claude sees with a structured summary.
#
# Trigger: tool output > 50 lines AND command matches a known verbose pattern.
# Disable: SUPERCHARGER_BASH_COMPACTOR=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_BASH_COMPACTOR:-1}" = "0" ] && exit 0

_INPUT=$(cat)

# v2.6.25: bash fast-path before any fork. Most Bash commands aren't verbose
# patterns (git log / pytest / vitest / jest / mocha / ava / npm test / npm
# install / cargo test). Scan the raw stdin once — if no trigger token is
# present, exit immediately. Median 110ms → ~0ms on the common case.
case "$_INPUT" in
  *'git log'*|*'npm test'*|*'pnpm test'*|*'yarn test'*|*vitest*|*jest*|*mocha*|*ava*|\
  *pytest*|*'go test'*|*'cargo test'*|*'npm install'*|*'pnpm install'*|*'yarn install'*|\
  *'pnpm add'*|*'npm i'*) ;;
  *) exit 0 ;;
esac

# Single jq fork extracts all four fields at once — replaces the previous
# four sequential jq calls (~50ms × 4 = ~200ms saved per invocation when bash
# output is short). Fields are joined with US separator (\x1f) so they can
# never appear in command/output.
FIELDS=$(printf '%s\n' "$_INPUT" | jq -r '[.cwd // "", .tool_name // "", .tool_input.command // "", .tool_response.stdout // .tool_response.output // ""] | @tsv' 2>/dev/null || true)
PROJECT_DIR=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $1}'); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "bash-output-compactor" && exit 0
hook_profile_skip "bash-output-compactor" && exit 0

TOOL_NAME=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $2}')
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $3}')
[ -z "$CMD" ] && exit 0

# Detect verbose pattern type — fast bash regex, no fork
PATTERN=""
case "$CMD" in
  *git\ log*) PATTERN="git-log" ;;
  *npm\ test*|*pnpm\ test*|*yarn\ test*) PATTERN="test" ;;
  *vitest*|*jest*|*mocha*|*ava*) PATTERN="test" ;;
  *pytest*|*python\ -m\ pytest*) PATTERN="test" ;;
  *go\ test*) PATTERN="test" ;;
  *cargo\ test*) PATTERN="test" ;;
  *npm\ install*|*pnpm\ install*|*yarn\ install*|*pnpm\ add*|*npm\ i*) PATTERN="install" ;;
  *) exit 0 ;;
esac

# Get tool output (stdout). Bash hook payloads include it under tool_response.stdout.
OUTPUT=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null || true)
[ -z "$OUTPUT" ] && exit 0

LINE_COUNT=$(printf '%s\n' "$OUTPUT" | wc -l | tr -d ' ')
[ "$LINE_COUNT" -lt 50 ] && exit 0

COMPACTED=$(PATTERN="$PATTERN" OUTPUT="$OUTPUT" LINE_COUNT="$LINE_COUNT" python3 <<'PYEOF'
import os, re

pattern = os.environ.get('PATTERN', '')
output = os.environ.get('OUTPUT', '')
line_count = int(os.environ.get('LINE_COUNT', 0))
lines = output.splitlines()

if pattern == 'git-log':
    head = lines[:5]
    tail = lines[-5:] if line_count > 10 else []
    summary = '\n'.join(head)
    if tail:
        summary += f'\n... [{line_count - 10} commits omitted] ...\n' + '\n'.join(tail)
    print(summary)

elif pattern == 'test':
    # Extract pass/fail counts
    pass_match = re.search(r'(\d+)\s+passed', output, re.IGNORECASE)
    fail_match = re.search(r'(\d+)\s+failed', output, re.IGNORECASE)
    skip_match = re.search(r'(\d+)\s+skipped', output, re.IGNORECASE)
    err_match  = re.search(r'(\d+)\s+errors?', output, re.IGNORECASE)
    duration   = re.search(r'(?:in|took|finished in)\s+([\d.]+\s*[ms]+)', output, re.IGNORECASE)

    parts = []
    if pass_match: parts.append(f'{pass_match.group(1)} passed')
    if fail_match: parts.append(f'{fail_match.group(1)} failed')
    if skip_match: parts.append(f'{skip_match.group(1)} skipped')
    if err_match:  parts.append(f'{err_match.group(1)} errors')
    summary_line = ', '.join(parts) if parts else f'{line_count} lines of test output'
    if duration: summary_line += f' (in {duration.group(1)})'

    # Find failure block — keep last 25 lines around 'FAIL' / 'failed' / 'Error'
    fail_indices = [i for i, l in enumerate(lines) if re.search(r'(FAIL|✗|❌|Error:|AssertionError|expect)', l)]
    if fail_indices:
        start = max(0, fail_indices[0] - 5)
        end = min(len(lines), fail_indices[-1] + 20)
        # Cap excerpt at 30 lines
        if end - start > 30:
            end = start + 30
        excerpt = '\n'.join(lines[start:end])
        print(f'[Test summary] {summary_line}\n[Failure excerpt — {end-start} lines]\n{excerpt}')
    else:
        print(f'[Test summary] {summary_line}\n[All passed — {line_count} lines suppressed]')

elif pattern == 'install':
    # Find "added N packages" / "X packages installed"
    added = re.search(r'(\d+)\s+packages?(?:\s+(?:added|installed|updated))?', output, re.IGNORECASE)
    duration = re.search(r'(?:in|took)\s+([\d.]+\s*[ms]+)', output, re.IGNORECASE)
    summary_line = []
    if added: summary_line.append(f'{added.group(1)} packages')
    if duration: summary_line.append(f'in {duration.group(1)}')

    # Show only warnings/errors from output
    relevant = [l for l in lines if re.search(r'\b(warn|error|failed|deprecated|peer dep)', l, re.IGNORECASE)]
    relevant = relevant[:15]

    base = '[Install summary] ' + (', '.join(summary_line) if summary_line else f'{line_count} lines')
    if relevant:
        base += '\n[Warnings/errors (' + str(len(relevant)) + ')]\n' + '\n'.join(relevant)
    else:
        base += '\n[No warnings or errors]'
    print(base)
PYEOF
)

[ -z "$COMPACTED" ] && exit 0

OUT_JSON=$(printf '%s' "$COMPACTED" | jq -Rs '.' 2>/dev/null || true)
[ -z "$OUT_JSON" ] && exit 0

# Use v2.1.121 updatedToolOutput to replace Claude's view with the compacted summary.
# Original output is preserved in transcript log; only context-injected version is compacted.
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":%s}}\n' "$OUT_JSON"
echo "[Supercharger] bash-output-compactor: compressed $LINE_COUNT-line $PATTERN output" >&2

exit 0
