#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/setup-check.sh"

echo "=== Setup Check Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "setup-check: emits healthy status when install is intact"
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qE "Setup check|systemMessage" && pass || fail "no status emitted, got: $OUT"

begin_test "setup-check: includes version in status"
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qE "v[0-9]+\.[0-9]+\.[0-9]+|vunknown" && pass || fail "no version in status: $OUT"

begin_test "setup-check: drains stdin without error on empty input"
OUT=$(echo '' | bash "$HOOK" 2>&1)
EXIT=$?
[ "$EXIT" -eq 0 ] && pass || fail "non-zero exit on empty stdin: $EXIT"

begin_test "setup-check: drains stdin without error on arbitrary payload"
OUT=$(echo '{"reason":"--maintenance"}' | bash "$HOOK" 2>&1)
EXIT=$?
[ "$EXIT" -eq 0 ] && pass || fail "non-zero exit on --maintenance payload: $EXIT"

begin_test "setup-check: emits valid JSON to stdout"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | python3 -c "import json,sys; json.loads(sys.stdin.read())" 2>/dev/null && pass || fail "invalid JSON on stdout: $OUT"

report
