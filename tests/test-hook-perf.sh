#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/hook-perf.sh"

echo "=== Hook Performance Profiler Tests ==="

begin_test "hook-perf: runs without error on empty audit dir"
TMPDIR_EMPTY=$(mktemp -d)
OUTPUT=$(bash "$TOOL" --audit "$TMPDIR_EMPTY" 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  pass
else
  fail "expected exit 0 on empty audit dir, got $EXIT_CODE: $OUTPUT"
fi
rm -rf "$TMPDIR_EMPTY"

begin_test "hook-perf: parses elapsed_ms from JSONL entries"
TMPDIR_DATA=$(mktemp -d)
cat > "$TMPDIR_DATA/hooks.jsonl" << 'JSONL'
{"timestamp":"2026-04-22T14:00:00Z","hook":"safety.sh","elapsed_ms":12}
{"timestamp":"2026-04-22T14:00:01Z","hook":"safety.sh","elapsed_ms":10}
{"timestamp":"2026-04-22T14:00:02Z","hook":"safety.sh","elapsed_ms":14}
JSONL
OUTPUT=$(bash "$TOOL" --audit "$TMPDIR_DATA" --days 1 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -q "safety.sh"; then
  pass
else
  fail "expected 'safety.sh' in output, got exit $EXIT_CODE: $OUTPUT"
fi
rm -rf "$TMPDIR_DATA"

begin_test "hook-perf: --slow filters to hooks averaging >50ms"
TMPDIR_SLOW=$(mktemp -d)
cat > "$TMPDIR_SLOW/hooks.jsonl" << 'JSONL'
{"timestamp":"2026-04-22T14:00:00Z","hook":"safety.sh","elapsed_ms":12}
{"timestamp":"2026-04-22T14:00:01Z","hook":"safety.sh","elapsed_ms":10}
{"timestamp":"2026-04-22T14:00:02Z","hook":"code-security-scanner.sh","elapsed_ms":89}
{"timestamp":"2026-04-22T14:00:03Z","hook":"code-security-scanner.sh","elapsed_ms":95}
JSONL
OUTPUT=$(bash "$TOOL" --audit "$TMPDIR_SLOW" --days 1 --slow 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ] && ! echo "$OUTPUT" | grep -q "safety.sh"; then
  pass
else
  fail "--slow should exclude safety.sh (avg ~12ms); got exit $EXIT_CODE: $OUTPUT"
fi
rm -rf "$TMPDIR_SLOW"

begin_test "hook-perf: --json outputs valid JSON"
TMPDIR_JSON=$(mktemp -d)
cat > "$TMPDIR_JSON/hooks.jsonl" << 'JSONL'
{"timestamp":"2026-04-22T14:00:00Z","hook":"safety.sh","elapsed_ms":12}
{"timestamp":"2026-04-22T14:00:01Z","hook":"safety.sh","elapsed_ms":15}
JSONL
OUTPUT=$(bash "$TOOL" --audit "$TMPDIR_JSON" --days 1 --json 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  pass
else
  fail "--json output is not valid JSON (exit $EXIT_CODE): $OUTPUT"
fi
rm -rf "$TMPDIR_JSON"

report
