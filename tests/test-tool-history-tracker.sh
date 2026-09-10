#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/tool-history-tracker.sh"

echo "=== tool-history-tracker Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "tool-history-tracker: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "tool-history-tracker: appends success entry to per-session file"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
[ -s "$HISTORY" ] && pass || fail "history not written"
teardown_test_home

# v4.0.48: the bound is now 40, trimmed down to 20 — not "never above 20".
# Trimming AT 20 meant the condition was true forever past the 20th tool call, so
# every single call forked wc + tail + mv to remove ONE line. Measured A/B on the
# same machine and harness: 19.2 -> 10.0 cpu-ms per call.
#
# The ≤20 contract this test used to assert was not load-bearing: the only
# consumer, confidence-gate.sh:134, reads the last 5 entries. What IS load-bearing
# is that the file stays BOUNDED, so that is what is asserted now — a widened
# number alone would have been the contract quietly slipping.
begin_test "tool-history-tracker: trims to 20 entries per-session"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history-sess1"
for i in $(seq 1 25); do
  echo "{\"session_id\":\"sess1\",\"tool\":\"Read\",\"success\":true,\"ts\":$i}"
done > "$HISTORY"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
[ "$COUNT" -le 40 ] && pass || fail "expected ≤40 entries, got $COUNT"

begin_test "tool-history-tracker: and the trim actually FIRES, so it stays bounded"
# The control for the assertion above: ≤40 is also satisfied by a hook that never
# trims at all until it happens to be under the cap. Push well past the trigger
# and prove the file came back DOWN.
for i in $(seq 1 60); do
  echo "{\"session_id\":\"sess1\",\"tool\":\"Read\",\"success\":true,\"ts\":$i}"
done > "$HISTORY"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
COUNT2=$(wc -l < "$HISTORY" | tr -d ' ')
[ "$COUNT2" -le 21 ] && pass || fail "60 entries were not trimmed back down (got $COUNT2)"
teardown_test_home

# v2.7.30: PostToolUse tool_response has no exit_code — failure is inferred from
# interrupted or strong stderr markers (real Bash tool_response shape).
begin_test "tool-history-tracker: marks success=false on failed bash (stderr marker)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history-sess1"
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_response":{"interrupted":false,"stdout":"","stderr":"bash: foo: command not found"}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
grep -q '"success": false' "$HISTORY" && pass || fail "expected success:false in history"

begin_test "tool-history-tracker: marks success=false when interrupted"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history-sess1"
echo '{"session_id":"sess1","tool_name":"Bash","tool_response":{"interrupted":true,"stdout":"","stderr":""}}' | bash "$HOOK" >/dev/null 2>&1 || true
grep -q '"success": false' "$HISTORY" && pass || fail "expected success:false on interrupted"
teardown_test_home

begin_test "tool-history-tracker: per-session isolation — sess A doesn't see sess B"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY_A="$HOME/.claude/supercharger/scope/.tool-history-sessA"
HISTORY_B="$HOME/.claude/supercharger/scope/.tool-history-sessB"
echo '{"session_id":"sessA","tool_name":"Edit","tool_response":{}}' | bash "$HOOK" >/dev/null 2>&1 || true
echo '{"session_id":"sessB","tool_name":"Bash","tool_response":{}}' | bash "$HOOK" >/dev/null 2>&1 || true
GREP_A=$( ( [ -f "$HISTORY_A" ] && grep -c 'sessA' "$HISTORY_A" ) 2>/dev/null | tr -d ' \n' || echo 0)
GREP_B=$( ( [ -f "$HISTORY_B" ] && grep -c 'sessB' "$HISTORY_B" ) 2>/dev/null | tr -d ' \n' || echo 0)
LEAK_A=$( ( [ -f "$HISTORY_A" ] && grep -c 'sessB' "$HISTORY_A" ) 2>/dev/null | tr -d ' \n' || echo 0)
LEAK_B=$( ( [ -f "$HISTORY_B" ] && grep -c 'sessA' "$HISTORY_B" ) 2>/dev/null | tr -d ' \n' || echo 0)
GREP_A=${GREP_A:-0}; GREP_B=${GREP_B:-0}; LEAK_A=${LEAK_A:-0}; LEAK_B=${LEAK_B:-0}
if [ "$GREP_A" -ge 1 ] && [ "$GREP_B" -ge 1 ] && [ "$LEAK_A" -eq 0 ] && [ "$LEAK_B" -eq 0 ]; then
  pass
else
  fail "expected isolation: A=$GREP_A B=$GREP_B leakA=$LEAK_A leakB=$LEAK_B"
fi
teardown_test_home

report
