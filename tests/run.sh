#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# v2.23.8: keep the whole suite from popping REAL desktop notifications. Hooks
# that notify on a block (elicitation-guard, notify-*) honor this; the two notify
# test files unset it so they can still exercise the (mocked) send path.
export SUPERCHARGER_NO_NOTIFY=1

TOTAL_PASSED=0
TOTAL_FAILED=0

echo ""
echo "Claude Supercharger — Test Suite"
echo "================================"
echo ""

# Parallel execution in waves of $TEST_JOBS.
#
# The suite is ~2500 assertions and each one forks a hook (which forks python3
# or jq), so wall time was ~7 minutes of almost entirely serial fork overhead —
# no single slow file, just a long tail. Test files are independent, so they run
# concurrently and their output is replayed in glob order afterwards, keeping
# the report byte-comparable to the serial version.
#
# Waves (batch, wait, batch) rather than a work queue: bash 3.2 has no `wait -n`,
# and xargs -P would need `bash -c` plus an exported function. A wave is gated by
# its slowest file, which is good enough here and far easier to reason about.
#
# TEST_JOBS=1 restores fully serial execution for debugging an ordering-sensitive
# failure.
if [ -z "${TEST_JOBS:-}" ]; then
  TEST_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
fi

RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

# Each file runs under its own HOME.
#
# Without this, hooks under test write to the real ~/.claude/supercharger:
# .blocked-commands (which feeds the [BLOCKS] summary injected into every
# session, so test fixtures were being counted as real security events),
# .safety-trace.log and .scan-alert-*. Only 40 of the ~152 files call
# setup_test_home, so the other 112 inherited the developer's real HOME.
# It is also what makes parallel execution safe — two files appending to one
# .blocked-commands would interleave.
#
# HOME rather than SUPERCHARGER_STATE, deliberately: the tests read state back
# through "$HOME/.claude/supercharger/scope/..." literals while the hooks resolve
# it via lib-paths.sh. Overriding only STATE splits those two apart — the hook
# writes to the temp dir and the assertion looks in the real one — which fails
# ~160 assertions. Overriding HOME keeps both sides resolving to the same place.
#
# SUPERCHARGER_HOME is deliberately NOT set: it is the read-only code root and
# still resolves off the real HOME to the installed copy. Pointing it at this
# repo breaks asset lookups, since install.sh flattens configs/economy and
# configs/roles to the top level.
run_one() {
  local tf="$1" name home
  name=$(basename "$tf" .sh)
  home=$(mktemp -d)
  # Canonicalise: on macOS `mktemp -d` yields /var/folders/... and /var is a
  # symlink to /private/var. path-guard realpaths paths to stop an in-path
  # symlink abusing its memory-store allowance, so a symlinked HOME trips that
  # check and wrongly denies a write the test expects to be allowed. Real homes
  # (/Users/x, /home/x) are already canonical, so this only removes an artefact
  # of the temp dir rather than weakening the guard.
  home=$(cd "$home" && pwd -P)
  mkdir -p "$home/.claude"
  HOME="$home" bash "$tf" "$REPO_DIR" > "$RESULT_DIR/$name.out" 2>&1 || true
  rm -rf "$home"
}

running=0
for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$test_file" ] || continue
  run_one "$test_file" &
  running=$((running + 1))
  if [ "$running" -ge "$TEST_JOBS" ]; then
    wait
    running=0
  fi
done
wait

# Replay in glob order so the report is deterministic regardless of finish order.
for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$test_file" ] || continue
  test_name=$(basename "$test_file" .sh)
  echo "--- $test_name ---"

  output=$(cat "$RESULT_DIR/$test_name.out" 2>/dev/null || true)
  echo "$output"

  # tail -1: take the REPORT line only. This grepped every match in the file's
  # whole output, so a test whose name or echoed tool output contained "0 failed"
  # yielded two numbers and $(( )) died with "syntax error in expression" — the
  # suite then reported a partial total (286) as if it were the real one. report()
  # always prints last, so the final match is the authoritative count.
  passed=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1)
  failed=$(echo "$output" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | tail -1)
  [ -z "$passed" ] && passed=0
  [ -z "$failed" ] && failed=0

  TOTAL_PASSED=$((TOTAL_PASSED + passed))
  TOTAL_FAILED=$((TOTAL_FAILED + failed))
  echo ""
done

echo "================================"
echo "Total: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo ""

# --- README tests-badge parity ------------------------------------------------
# TOTAL_PASSED is the only place the true count exists, so the check lives here
# rather than in test-version-parity.sh — that test would have to run the whole
# suite to know the number, or duplicate it into a second file that can itself
# drift. (test-version-parity.sh covers the *version* badge; nothing covered this
# one, and it drifted 2430 vs 2436 by 2.24.5.)
#
# tools/release.sh already rewrites the badge on every release, so the normal
# path never trips this. What it catches is a hand-commit that adds tests without
# going through release.sh.
#
# Warn locally, fail in CI: a stale doc badge should not turn someone's suite red
# mid-edit, but it must not reach master either. GitHub Actions sets CI=true.
BADGE_DRIFT=0
# sed, not a second grep: '%20' contains digits, so grep -oE '[0-9]+' would
# yield both the count and 20. Same extraction shape as test-version-parity.sh:37.
BADGE=$(grep -oE 'tests-[0-9]+%20passing' "$REPO_DIR/README.md" 2>/dev/null | head -1 | sed 's/tests-\([0-9]*\)%20passing/\1/' || true)
# Compared against passed+failed, not passed alone: a failing test still exists,
# so a red run would otherwise report the badge as stale on top of the real
# failure and send the reader after the wrong bug. (It did — a flaky
# test-install.sh made the badge check cry drift for two releases.)
TOTAL_RUN=$((TOTAL_PASSED + TOTAL_FAILED))
if [ -n "$BADGE" ] && [ "$BADGE" != "$TOTAL_RUN" ]; then
  echo "WARNING: README tests badge says ${BADGE}, suite has ${TOTAL_RUN}."
  echo "         Bump it to ${TOTAL_RUN} (tools/release.sh does this automatically on release)."
  echo ""
  if [ -n "${CI:-}" ]; then
    BADGE_DRIFT=1
  fi
fi

# --- Agent Eval (opt-in: costs real API tokens) ---
if [[ "${RUN_EVAL:-false}" == "true" ]]; then
  echo ""
  echo "Running agent evals (RUN_EVAL=true — makes real API calls)..."
  bash "$(dirname "$0")/eval-agents.sh"
fi

if [ "$TOTAL_FAILED" -gt 0 ]; then
  exit 1
fi
if [ "$BADGE_DRIFT" -ne 0 ]; then
  echo "FAIL: README tests badge is stale (see warning above)."
  exit 1
fi
exit 0
