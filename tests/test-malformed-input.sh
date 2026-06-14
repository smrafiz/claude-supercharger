#!/usr/bin/env bash
# Regression guard for the v2.6.8/v2.6.10 fix:
# `set -euo pipefail` + jq (or python3) on stdin used to crash silently
# whenever the input wasn't valid JSON. New hooks that forget `|| true`
# after their input-parsing pipeline will re-introduce the bug. This test
# pipes invalid JSON into every hook and asserts each exits 0.
#
# Excludes are limited to library files that aren't event handlers.

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== malformed-input regression Tests ==="

setup_test_home

CRASHED=()
PASSED=0
for h in "$REPO_DIR"/hooks/*.sh; do
  name=$(basename "$h" .sh)
  case "$name" in
    lib-*|webhook-lib|notify-helper) continue ;;
  esac
  begin_test "$name: survives malformed JSON input"
  if echo '{not valid json' | bash "$h" >/dev/null 2>&1; then
    pass
    PASSED=$((PASSED + 1))
  else
    fail "hook exited non-zero on malformed JSON (regression of v2.6.10 fix)"
    CRASHED+=("$name")
  fi
done

teardown_test_home

echo ""
if [ ${#CRASHED[@]} -gt 0 ]; then
  echo "Crashed: ${CRASHED[*]}"
fi
echo "$TESTS_PASSED passed, $TESTS_FAILED failed ($((TESTS_PASSED + TESTS_FAILED)) total)"
exit $TESTS_FAILED
