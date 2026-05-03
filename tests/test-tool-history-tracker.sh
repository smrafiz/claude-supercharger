#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/tool-history-tracker.sh"

echo "=== tool-history-tracker Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "tool-history-tracker: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "tool-history-tracker: appends success entry"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
[ -s "$HISTORY" ] && pass || fail "history not written"
teardown_test_home

begin_test "tool-history-tracker: trims to 20 entries"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
for i in $(seq 1 25); do
  echo "{\"session_id\":\"old\",\"tool\":\"Read\",\"success\":true,\"ts\":$i}"
done > "$HISTORY"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
[ "$COUNT" -le 20 ] && pass || fail "expected ≤20 entries, got $COUNT"
teardown_test_home

begin_test "tool-history-tracker: marks success=false when exit_code != 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_response":{"exit_code":1}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
grep -q '"success": false' "$HISTORY" && pass || fail "expected success:false in history"
teardown_test_home

report
