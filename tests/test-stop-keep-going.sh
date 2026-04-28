#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/stop-keep-going.sh"

echo "=== Stop Keep-Going Tests ==="

# Helper to set up keep-going flag
enable_keep_going() {
  mkdir -p "$HOME/.claude/supercharger/scope"
  touch "$HOME/.claude/supercharger/scope/.keep-going"
}

begin_test "stop-keep-going: disabled by default (no flag, no env)"
setup_test_home
INPUT='{"last_assistant_message":"Should I continue with the next step?","cwd":"/tmp","session_id":"t1"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should not poke when disabled"
teardown_test_home

begin_test "stop-keep-going: nudges when 'Should I continue'"
setup_test_home
enable_keep_going
INPUT='{"last_assistant_message":"I have refactored the function. Should I continue with the test updates?","cwd":"/tmp","session_id":"t2"}'
OUT=$(printf '%s' "$INPUT" | SUPERCHARGER_KEEP_GOING=1 bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q '"decision":"block"' && pass || fail "should block when asking to continue"
teardown_test_home

begin_test "stop-keep-going: nudges when 'Want me to'"
setup_test_home
enable_keep_going
INPUT='{"last_assistant_message":"The first part is done. Want me to also handle the edge cases?","cwd":"/tmp","session_id":"t3"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q '"decision":"block"' && pass || fail "should block when asking permission"
teardown_test_home

begin_test "stop-keep-going: does NOT nudge when work is complete"
setup_test_home
enable_keep_going
INPUT='{"last_assistant_message":"All tests pass. The feature is done and ready for review.","cwd":"/tmp","session_id":"t4"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should not poke conclusive completion"
teardown_test_home

begin_test "stop-keep-going: does NOT nudge for short messages"
setup_test_home
enable_keep_going
INPUT='{"last_assistant_message":"Done.","cwd":"/tmp","session_id":"t5"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should skip very short messages"
teardown_test_home

begin_test "stop-keep-going: caps pokes at 3 per session"
setup_test_home
enable_keep_going
mkdir -p "$HOME/.claude/supercharger/scope"
printf '2026-04-27T00:00:00Z\n2026-04-27T00:01:00Z\n2026-04-27T00:02:00Z\n' > "$HOME/.claude/supercharger/scope/.keep-going-cap1"
INPUT='{"last_assistant_message":"Should I continue with the next refactor?","cwd":"/tmp","session_id":"cap1"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should stop poking after 3 nudges"
teardown_test_home

begin_test "stop-keep-going: nudges when 'Let me know if'"
setup_test_home
enable_keep_going
INPUT='{"last_assistant_message":"I implemented the basic flow. Let me know if you want me to add validation as well.","cwd":"/tmp","session_id":"t7"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q '"decision":"block"' && pass || fail "should block 'let me know'"
teardown_test_home

begin_test "stop-keep-going: no output for malformed input"
setup_test_home
enable_keep_going
OUT=$(printf '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty input"
teardown_test_home

report
