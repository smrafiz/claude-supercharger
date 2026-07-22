#!/usr/bin/env bash
# Suite for trace-compactor.sh (v2.21.11).
# The hook's scope is Python/Node tracebacks. Its old generic else-branch
# silently rewrote ANY >=2000-char Bash output (first-2000 + last-500) via
# updatedToolOutput, hiding the middle so Claude acted on it as if complete.
# Now generic truncation is opt-in; tracebacks still compact.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/trace-compactor.sh"

# build a >2000-char python traceback
PY_TB=$(python3 - <<'PY'
tb = "Traceback (most recent call last):\n"
for i in range(60):
    tb += '  File "/app/mod%d.py", line %d, in fn%d\n    do_something_%d()\n' % (i, i*7, i, i)
tb += "ValueError: something broke\n"
print(tb)
PY
)
# build a >2000-char plain output (NOT a traceback)
PLAIN=$(python3 -c "print(chr(10).join('data line %d with content here' % i for i in range(200)))")

jout() { python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','cwd':'/tmp','tool_response':{'stdout':sys.stdin.read()}}))"; }

begin_test "trace-compactor: python traceback is still compacted"
OUT=$(printf '%s' "$PY_TB" | jout | bash "$H" 2>/dev/null)
echo "$OUT" | grep -q 'TRACEBACK COMPACTED' && pass || fail "traceback not compacted: ${OUT:0:80}"

begin_test "trace-compactor: generic large output is NOT rewritten by default (no updatedToolOutput)"
OUT=$(printf '%s' "$PLAIN" | jout | bash "$H" 2>/dev/null)
echo "$OUT" | grep -q 'updatedToolOutput' && fail "generic output silently truncated (middle hidden): ${OUT:0:80}" || pass

begin_test "trace-compactor: generic truncation works when opted in"
OUT=$(printf '%s' "$PLAIN" | jout | SUPERCHARGER_TRACE_COMPACT_GENERIC=1 bash "$H" 2>/dev/null)
echo "$OUT" | grep -q 'updatedToolOutput' && pass || fail "opt-in generic truncation did not fire: ${OUT:0:80}"

begin_test "trace-compactor: short output is ignored (exit 0, no output)"
OUT=$(printf '%s' "hello short" | jout | bash "$H" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "short output produced hook output: ${OUT:0:80}"

report
