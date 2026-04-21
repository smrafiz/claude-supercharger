#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/session-analytics.sh"

echo "=== Session Analytics Tests ==="

begin_test "session-analytics: script exists and is executable"
if [ -f "$TOOL" ] && [ -x "$TOOL" ]; then
  pass
else
  fail "expected $TOOL to exist and be executable"
fi

begin_test "session-analytics: --help exits 0"
bash "$TOOL" --help >/dev/null 2>&1
assert_exit_code 0 $? && pass

begin_test "session-analytics: missing projects dir exits 0 with message"
OUTPUT=$(bash "$TOOL" --projects /nonexistent/path 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -qi "no session data"; then
  pass
else
  fail "expected exit 0 and 'no session data' message, got exit $EXIT_CODE: $OUTPUT"
fi

report
