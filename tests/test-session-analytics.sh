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

begin_test "session-analytics: synthetic fixture produces correct cost"
TMPDIR_FIXTURE=$(mktemp -d)
mkdir -p "$TMPDIR_FIXTURE/proj-foo"
# 1 assistant turn: input=1,000,000 tokens, all others 0
# Expected cost: 1000000 * $3.00/1M = $3.00
cat > "$TMPDIR_FIXTURE/proj-foo/session1.jsonl" << 'JSONL'
{"type":"user","timestamp":"2026-04-21T10:00:00Z","message":{"content":"hello"}}
{"type":"assistant","timestamp":"2026-04-21T10:00:01Z","message":{"usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
JSONL

OUTPUT=$(bash "$TOOL" --projects "$TMPDIR_FIXTURE" --days 7 2>&1)
if echo "$OUTPUT" | grep -qE '\$\s*3\.00'; then
  pass
else
  fail "expected \$3.00 in output, got: $OUTPUT"
fi
rm -rf "$TMPDIR_FIXTURE"

report
