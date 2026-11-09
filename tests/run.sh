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

# Parallel execution, at most $TEST_JOBS files at a time.
#
# The suite is ~2500 assertions and each one forks a hook (which forks python3
# or jq), so wall time was ~7 minutes of almost entirely serial fork overhead —
# no single slow file, just a long tail. Test files are independent, so they run
# concurrently and their output is replayed in glob order afterwards, keeping
# the report byte-comparable to the serial version.
#
# A pool that polls `jobs -pr` (bash 3.2 has no `wait -n`). It replaced waves
# (batch, wait, batch) on 2026-11-05: each wave waited for its slowest file, and
# a Windows shard ran 55m against 8-20m for the others.
#
# TEST_JOBS=1 restores fully serial execution for debugging an ordering-sensitive
# failure.
if [ -z "${TEST_JOBS:-}" ]; then
  TEST_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
fi

RESULT_DIR=$(mktemp -d)
# 2026-11-09: helpers.sh names each test home sc-test-home-<this run>-<pid>, and
# the sweep below removes only this run's homes. A bare sc-test-home-* glob let a
# NESTED run.sh (test-run-shard runs a fixture copy) delete the homes of every
# test file running at that moment: a dedup record vanished between two calls.
export SC_SUITE_RUN="$$"
# v2.26.47: keep the per-file output when the suite goes red.
#
# RESULT_DIR was always deleted on exit, so a failure that does not reproduce
# left nothing to inspect — which is the situation with an intermittent test.
# A ~1-in-5 single-assertion flip was seen here and could not be identified: it
# never reproduced in 36 isolated runs of the likeliest files, so it only exists
# under parallel execution, and re-running the whole suite to catch it costs
# ~5 minutes per attempt at a 20% hit rate.
#
# Preserving the directory turns that hunt into a passive trap: the NEXT red run
# leaves the exact per-file output on disk, for free. Kept only on failure, so a
# green run still cleans up after itself and nothing accumulates.
SC_KEEP_DIR="${TMPDIR:-/tmp}/sc-suite-failure-$$"
_sc_cleanup() {
  if [ "${TOTAL_FAILED:-0}" != "0" ]; then
    cp -R "$RESULT_DIR" "$SC_KEEP_DIR" 2>/dev/null \
      && echo "" >&2 \
      && echo "Per-file output kept for inspection: $SC_KEEP_DIR" >&2
  fi
  rm -rf "$RESULT_DIR"
  rm -rf "${TMPDIR:-/tmp}"/sc-test-home-"$SC_SUITE_RUN"-* 2>/dev/null || true
}
# Also sweep the per-test isolated state dirs from tests/helpers.sh. Tests that
# install their own EXIT trap replace the helper's cleanup, so without this the
# dirs accumulate in TMPDIR across runs.
trap _sc_cleanup EXIT

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

# v2.26.83: TEST_GLOB selects a subset of files. Added for the Windows job, which
# must run a WINDOWS-RELEVANT subset rather than everything: several test files
# build a PATH with `ln -sf`, and on Git Bash `ln -s` silently COPIES (measured,
# plan §11.1), so they would copy bash/python3 and report harness breakage as
# product failure. Default is unchanged, so mac/Linux keep running everything.
TEST_GLOB="${TEST_GLOB:-test-*.sh}"

# v2.27.46: TEST_SKIP excludes named files from an otherwise complete run. A glob
# can select a subset but cannot express "everything except these", and that is
# exactly what the Windows job needs to become GATING: 219 of 226 files already
# pass there, and the 7 that do not are known and tracked. Excluding those by
# name lets the other 219 fail the build, which is the whole point — a glob
# allowlist would silently drop every NEW test file out of Windows coverage,
# while a denylist puts new files under the gate by default. Space or newline
# separated basenames, with or without the .sh suffix.
_skip_this() {
  case " ${TEST_SKIP:-} " in
    *" $1 "*|*" $1.sh "*) return 0 ;;
  esac
  return 1
}

# TEST_SHARD=i/n splits the suite across n machines (1-based). The _HEAVY files are
# dealt out first (1,2,..n,n,..1) and run first; the rest go round robin in glob
# order, after TEST_SKIP, identically in the run and replay loops below. Unset runs
# everything.
_SHARD_I=0; _SHARD_N=1
case "${TEST_SHARD:-}" in
  '') ;;
  [1-9]*/[1-9]*) _SHARD_I=$(( ${TEST_SHARD%/*} - 1 )); _SHARD_N=${TEST_SHARD#*/} ;;
  *) echo "TEST_SHARD must be i/n, e.g. 2/4 (got '$TEST_SHARD')" >&2; exit 2 ;;
esac
if [ "$_SHARD_I" -ge "$_SHARD_N" ]; then
  echo "TEST_SHARD $TEST_SHARD: i must be 1..n" >&2; exit 2
fi
# Read once, then dropped: a test that runs tests/run.sh itself (test-run-shard,
# test-suite-count-invariance) would otherwise inherit this machine's shard and run
# a quarter of its own fixture. Found on the first sharded Windows run.
_SHARDED=${TEST_SHARD:+1}
unset TEST_SHARD
# Slowest files, slowest first (measured 2026-11-05). Round robin alone put the top
# two in one shard, which ran 55m on Windows against 8-20m for the others.
_HEAVY="test-command-prelude-matrix test-hooks test-perf-chain test-credential-access-matrix \
test-safety-bash-evasions test-list-hooks test-safety-fp test-download-execute-matrix \
test-claude-md-marker test-claim-evidence-gate test-cloud-cli-destructive-guard \
test-hook-contracts test-install test-bash-injection-scanner test-deny-rule-fp test-sweep5"
_is_heavy() { case " $_HEAVY " in *" $1 "*) return 0 ;; esac; return 1; }
# _pick <name>: is this file in our shard? Advances _n for non-heavy files.
_pick() {
  local k=0 h r
  if _is_heavy "$1"; then
    for h in $_HEAVY; do [ "$h" = "$1" ] && break; k=$((k + 1)); done
    r=$(( k % (2 * _SHARD_N) )); [ "$r" -ge "$_SHARD_N" ] && r=$(( 2 * _SHARD_N - 1 - r ))
  else
    r=$(( _n % _SHARD_N )); _n=$((_n + 1))
  fi
  [ "$r" -eq "$_SHARD_I" ]
}

_n=0
_launch() {
  [ -f "$1" ] || return 0
  _t=$(basename "$1" .sh)
  _skip_this "$_t" && return 0
  _pick "$_t" || return 0
  run_one "$1" &
  # A pool, not waves: start the next file as soon as any one finishes. Waves of
  # TEST_JOBS each waited for their slowest file. bash 3.2 has no `wait -n`.
  while [ "$(jobs -pr | wc -l)" -ge "$TEST_JOBS" ]; do sleep 0.2; done
}
for h in $_HEAVY; do
  # shellcheck disable=SC2254 # TEST_GLOB is a glob on purpose
  case "$h.sh" in $TEST_GLOB) _launch "$SCRIPT_DIR/$h.sh" ;; esac
done
for test_file in "$SCRIPT_DIR"/$TEST_GLOB; do
  _is_heavy "$(basename "$test_file" .sh)" && continue
  _launch "$test_file"
done
wait

_n=0
# Replay in glob order so the report is deterministic regardless of finish order.
# Must use the SAME glob as the run loop above, or a subset run replays files it
# never executed and reports them as empty.
for test_file in "$SCRIPT_DIR"/$TEST_GLOB; do
  [ -f "$test_file" ] || continue
  test_name=$(basename "$test_file" .sh)
  # Same exclusion as the run loop, or the replay reports files that never ran.
  _skip_this "$test_name" && continue
  _pick "$test_name" || continue
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
# v2.26.83: a SUBSET run must not judge the badge — it counts a fraction of the
# suite, so it would always report drift and, worse, `BADGE_DRIFT=1` would fail
# the Windows job for a number that is correct.
if [ "$TEST_GLOB" != 'test-*.sh' ] || [ -n "$_SHARDED" ]; then
  BADGE=""
fi
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
# v4.0.46: a run that executed NO tests is not a pass. "Total: 0 passed, 0
# failed" exited 0, and this is the gate tools/release.sh runs on a clean
# checkout before every release — so a TEST_GLOB or TEST_SKIP that selects
# nothing (a typo, a renamed file, a bad path) would have shipped a release on a
# suite that ran nothing and said so in green.
#
# Not hypothetical for the config that needs it most: the Windows job is the one
# caller that sets both TEST_GLOB and TEST_SKIP, so it is the one place where a
# single typo silently empties the run.
#
# A file that ABORTS mid-run already fails correctly (measured: rc=1); the hole
# was only the empty selection. Borrowed from scott-garvin/claude-code-guardrails,
# whose verify-before-claim skill names this shape "green-by-skip".
if [ "$TOTAL_RUN" -eq 0 ]; then
  echo "FAIL: the suite ran 0 tests — that is not a pass."
  echo "      TEST_GLOB='${TEST_GLOB}' matched no files under $(dirname "$0")."
  exit 1
fi
if [ "$BADGE_DRIFT" -ne 0 ]; then
  echo "FAIL: README tests badge is stale (see warning above)."
  exit 1
fi
exit 0
