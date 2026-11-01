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
echo "$OUT" | grep -q 'frames collapsed' && pass || fail "traceback not compacted: ${OUT:0:80}"

# 4.4.2: the old hook replaced the WHOLE output with one line when it held a
# traceback, so the rest of a test run vanished. Frames collapse; the rest stays.
_view() { python3 -c "import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)['hookSpecificOutput']['updatedToolOutput'] if d else '')"; }
RUN=$(python3 - <<'PY'
out = "tests/test_a.py::test_one PASSED\ntests/test_a.py::test_two PASSED\n"
out += "Traceback (most recent call last):\n"
out += '  File "/repo/app/main.py", line 10, in run\n    handle(req)\n'
for i in range(40):
    out += '  File "/usr/lib/python3.12/site-packages/fw/core%d.py", line %d, in call\n    return self.next(x)\n' % (i, i)
out += '  File "/repo/app/handler.py", line 42, in handle\n    raise KeyError(key)\n'
out += "KeyError: 'user_id'\n\n"
out += "During handling of the above exception, another exception occurred:\n\n"
out += "Traceback (most recent call last):\n"
out += '  File "/repo/app/main.py", line 12, in run\n    report(e)\n'
out += "RuntimeError: report failed\n"
out += "tests/test_b.py::test_three PASSED\nFAILED tests/test_a.py::test_four - KeyError: 'user_id'\n"
print(out)
PY
)
V=$(printf '%s' "$RUN" | jout | bash "$H" 2>/dev/null | _view)

begin_test "trace-compactor: the rest of a test run survives a traceback"
_lost=""
for want in 'test_one PASSED' 'test_two PASSED' 'test_three PASSED' 'FAILED tests/test_a.py::test_four'; do
  printf '%s' "$V" | grep -qF "$want" || _lost="$_lost '$want'"
done
[ -z "$_lost" ] && pass || fail "lost:$_lost"

begin_test "trace-compactor: exception lines and chained-exception lines are kept"
_lost=""
for want in "KeyError: 'user_id'" 'During handling of the above exception' 'RuntimeError: report failed'; do
  printf '%s' "$V" | grep -qF "$want" || _lost="$_lost '$want'"
done
[ -z "$_lost" ] && pass || fail "lost:$_lost"

begin_test "trace-compactor: library frames collapse, app frames and the innermost frame stay"
printf '%s' "$V" | grep -q 'library frames collapsed' \
  && printf '%s' "$V" | grep -qF '/repo/app/handler.py", line 42' \
  && printf '%s' "$V" | grep -qF '/repo/app/main.py", line 10' \
  && [ "$(printf '%s' "$V" | grep -c 'site-packages')" -le 5 ] && pass \
  || fail "got: $(printf '%s' "$V" | head -20)"

begin_test "trace-compactor: node_modules frames collapse, the error message stays"
NODE=$(python3 - <<'PY'
out = "TypeError: Cannot read properties of undefined (reading 'id')\n"
out += "    at getUser (/repo/src/users.js:12:9)\n"
for i in range(40):
    out += "    at Layer.handle (/repo/node_modules/express/lib/router/layer%d.js:95:5)\n" % i
out += "    at main (/repo/src/index.js:3:1)\n"
print(out)
PY
)
V=$(printf '%s' "$NODE" | jout | bash "$H" 2>/dev/null | _view)
printf '%s' "$V" | grep -qF "TypeError: Cannot read properties" && printf '%s' "$V" | grep -q 'library frames collapsed' \
  && printf '%s' "$V" | grep -qF '/repo/src/users.js:12:9' && pass || fail "got: $(printf '%s' "$V" | head -8)"

begin_test "trace-compactor: a short stack is left alone even in a long output"
SHORT=$(python3 -c "
print(chr(10).join('log line %d' % i for i in range(150)))
print('Traceback (most recent call last):')
print('  File \"/repo/a.py\", line 1, in f')
print('    g()')
print('ValueError: x')")
OUT=$(printf '%s' "$SHORT" | jout | bash "$H" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "rewrote a 1-frame traceback: ${OUT:0:80}"

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
