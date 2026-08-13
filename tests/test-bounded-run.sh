#!/usr/bin/env bash
# A subprocess bound that only exists where GNU coreutils does is not a bound.
#
# quality-gate and typecheck both wrapped their toolchain in `$TIMEOUT_CMD`,
# resolved from gtimeout → timeout → "". macOS ships neither (verified: `command
# -v timeout gtimeout` is empty on a stock Mac), and neither does Git Bash — so
# on two of the three supported platforms the wrapper expanded to nothing and
# eslint/prettier/ruff/tsc ran with no limit at all. The source read as protected
# the whole time.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Bounded Run Tests ==="

# shellcheck source=hooks/lib-bounded-run.sh
. "$REPO_DIR/hooks/lib-bounded-run.sh"

begin_test "a fast command returns its own exit status"
sc_bounded_run 5 true && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass || fail "expected 0, got $RC"

begin_test "a failing command's status is passed through, not swallowed"
sc_bounded_run 5 sh -c 'exit 7' && RC=0 || RC=$?
[ "$RC" -eq 7 ] && pass || fail "expected 7, got $RC"

begin_test "stdout is passed through so a call site can capture it"
OUT=$(sc_bounded_run 5 printf 'hello')
[ "$OUT" = "hello" ] && pass || fail "captured '$OUT'"

begin_test "stderr is passed through"
ERR=$(sc_bounded_run 5 sh -c 'printf oops >&2' 2>&1 >/dev/null)
[ "$ERR" = "oops" ] && pass || fail "captured '$ERR'"

# The reason the fallback backgrounds a killer instead of polling: a
# `while kill -0; do sleep 1; done` loop charges every call up to a full second,
# and quality-gate makes several per edit. This pins that it does not.
begin_test "a fast command adds no polling latency"
_T0=$(python3 -c 'import time; print(time.time())')
for _ in 1 2 3 4 5; do sc_bounded_run 30 true; done
_T1=$(python3 -c 'import time; print(time.time())')
_PER=$(python3 -c 'import sys; print("%.0f" % ((float(sys.argv[2]) - float(sys.argv[1])) * 1000 / 5))' "$_T0" "$_T1")
_OK=$(python3 -c 'import sys; print("1" if float(sys.argv[1]) < 250 else "0")' "$_PER")
[ "$_OK" = "1" ] && pass || fail "${_PER}ms per call — the bound is charging fast commands (polling?)"

begin_test "an overrunning command is killed and reports 124"
_T0=$(python3 -c 'import time; print(time.time())')
sc_bounded_run 1 sleep 20 && RC=0 || RC=$?
_T1=$(python3 -c 'import time; print(time.time())')
_EL=$(python3 -c 'import sys; print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$_T0" "$_T1")
_FAST=$(python3 -c 'import sys; print("1" if float(sys.argv[1]) < 8 else "0")' "$_EL")
if [ "$RC" -eq 124 ] && [ "$_FAST" = "1" ]; then
  pass
else
  fail "rc=$RC after ${_EL}s (expected 124 in ~1s)"
fi

# Killing the direct child is NOT enough, and this is the test that proves it:
# the shim below spawns a grandchild that holds the capture pipe, exactly like a
# linter wrapper does. Before the process-group kill, `issues=$(sc_bounded_run 2
# eslint …)` sat for the grandchild's full 20s with a 2s budget — the bound was
# reported as working by every simpler test.
#
# The liveness check uses a marker FILE, never `pgrep`/`pkill` on a command
# pattern: `pkill -f 'sleep 20'` matches any command LINE containing that text,
# which during development killed an unrelated background watcher in another
# session whose loop body was `sleep 20`. A test must not be able to do that.
begin_test "a grandchild holding the pipe is killed too, not just the direct child"
_BD=$(mktemp -d)
printf '#!/bin/sh\n( sleep 20; touch "%s/GRANDCHILD_LIVED" ) &\nwait\n' "$_BD" > "$_BD/wrapper.sh"
chmod +x "$_BD/wrapper.sh"
_T0=$(python3 -c 'import time; print(time.time())')
OUT=$(sc_bounded_run 1 "$_BD/wrapper.sh" 2>&1) || true
_T1=$(python3 -c 'import time; print(time.time())')
_EL=$(python3 -c 'import sys; print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$_T0" "$_T1")
_FAST=$(python3 -c 'import sys; print("1" if float(sys.argv[1]) < 8 else "0")' "$_EL")
if [ "$_FAST" != "1" ]; then
  fail "capture blocked ${_EL}s — the grandchild still held the pipe"
else
  sleep 1
  [ -f "$_BD/GRANDCHILD_LIVED" ] && fail "grandchild outlived the bound" || pass
fi
rm -rf "$_BD"

# --- the hooks that had the empty fallback ----------------------------------
begin_test "no hook resolves its timeout wrapper to an empty string"
BAD=""
for f in "$REPO_DIR"/hooks/*.sh; do
  grep -qE '^\s*(TIMEOUT_CMD|_TIMEOUT)=""' "$f" && BAD="$BAD $(basename "$f")"
done
[ -z "$BAD" ] && pass || fail "timeout wrapper expands to nothing (no bound on macOS/Git Bash):$BAD"

begin_test "quality-gate and typecheck bound their toolchain through the lib"
MISSING=""
for h in quality-gate typecheck; do
  grep -q 'sc_bounded_run' "$REPO_DIR/hooks/$h.sh" || MISSING="$MISSING $h"
  grep -q 'lib-bounded-run.sh' "$REPO_DIR/hooks/$h.sh" || MISSING="$MISSING $h(unsourced)"
done
[ -z "$MISSING" ] && pass || fail "not bounded:$MISSING"

begin_test "quality-gate still runs and stays silent on a clean file"
TD=$(mktemp -d)
printf 'x = 1\n' > "$TD/clean.py"
OUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$TD/clean.py" \
  | bash "$REPO_DIR/hooks/quality-gate.sh" 2>&1) || true
rm -rf "$TD"
printf '%s' "$OUT" | grep -q 'sc_bounded_run: command not found' \
  && fail "the lib is not reaching the linter call sites: $OUT" || pass

report
