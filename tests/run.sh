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

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  if [ ! -f "$test_file" ]; then
    continue
  fi

  test_name=$(basename "$test_file" .sh)
  echo "--- $test_name ---"

  # Run test in subshell so HOME changes don't leak
  output=$(bash "$test_file" "$REPO_DIR" 2>&1) || true
  echo "$output"

  # Extract pass/fail counts from last line
  passed=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo "0")
  failed=$(echo "$output" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo "0")

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
if [ -n "$BADGE" ] && [ "$BADGE" != "$TOTAL_PASSED" ]; then
  echo "WARNING: README tests badge says ${BADGE}, suite has ${TOTAL_PASSED}."
  echo "         Bump it to ${TOTAL_PASSED} (tools/release.sh does this automatically on release)."
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
