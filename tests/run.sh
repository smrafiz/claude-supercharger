#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

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

if [ "$TOTAL_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
