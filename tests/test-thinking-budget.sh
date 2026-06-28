#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/thinking-budget.sh"

# Test 1: low complexity prompt gets THINK injection
begin_test "thinking-budget: low complexity prompt gets THINK injection"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"show me the file","session_id":"default"}' | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -qi "THINK" && echo "$OUTPUT" | grep -qiE "trivial|minimal|directly"; then
  pass
else
  fail "expected low THINK message, got: $OUTPUT"
fi
teardown_test_home

# Test 2: high complexity prompt gets THINK injection
begin_test "thinking-budget: high complexity prompt gets THINK injection"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
LONG_PROMPT="design the authentication system for our multi-tenant SaaS platform, considering OAuth2, JWT, refresh token rotation, MFA, session management, rate limiting, and audit logging across all services"
OUTPUT=$(echo "{\"prompt\":\"$LONG_PROMPT\",\"session_id\":\"default\"}" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -qi "THINK" && echo "$OUTPUT" | grep -qiE "complex|thorough"; then
  pass
else
  fail "expected high THINK message, got: $OUTPUT"
fi
teardown_test_home

# Test 3: medium complexity prompt gets no injection
begin_test "thinking-budget: medium complexity prompt gets no injection"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"add a loading spinner to the button component","session_id":"default"}' | bash "$HOOK" 2>/dev/null)
if [ -z "$OUTPUT" ]; then
  pass
else
  fail "expected no output for medium prompt, got: $OUTPUT"
fi
teardown_test_home

# Test 4: uses agent classification when available
begin_test "thinking-budget: uses agent classification when available"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
# v2.6.77: agent-router writes the full named-persona; "Detective" lowercases to
# include "detective" which is now the high-thinking key (was 'debugger' which
# never matched any of the 9 real agent names).
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-classified-test-session"
touch "$HOME/.claude/supercharger/scope/.agent-classified-test-session"
OUTPUT=$(echo '{"prompt":"fix it","session_id":"test-session"}' | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -qi "THINK" && echo "$OUTPUT" | grep -qiE "complex|thorough"; then
  pass
else
  fail "expected high THINK from agent classification, got: $OUTPUT"
fi
teardown_test_home

# Test 5: yes/no prompt is low complexity
begin_test "thinking-budget: yes/no prompt is low complexity"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"yes","session_id":"default"}' | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -qi "THINK" && echo "$OUTPUT" | grep -qiE "trivial|minimal|directly"; then
  pass
else
  fail "expected low THINK message for 'yes', got: $OUTPUT"
fi
teardown_test_home

# v2.7.9 (B1a): dedup — same level twice within TTL collapses to one injection
begin_test "thinking-budget: dedups identical level within session"
setup_test_home
unset SUPERCHARGER_NO_DEDUP
mkdir -p "$HOME/.claude/supercharger/scope"
J='{"prompt":"debug this null pointer crash in the parser","session_id":"deduptb"}'
FIRST=$(echo "$J" | bash "$HOOK" 2>/dev/null | grep -c "THINK")
SECOND=$(echo "$J" | bash "$HOOK" 2>/dev/null | grep -c "THINK")
if [ "$FIRST" -eq 1 ] && [ "$SECOND" -eq 0 ]; then pass
else fail "expected first=1 second=0 (dedup), got first=$FIRST second=$SECOND"; fi
teardown_test_home

begin_test "thinking-budget: level change re-emits after dedup"
setup_test_home
unset SUPERCHARGER_NO_DEDUP
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"investigate and refactor the broken auth module","session_id":"chgtb"}' | bash "$HOOK" >/dev/null 2>&1
LOW=$(echo '{"prompt":"yes","session_id":"chgtb"}' | bash "$HOOK" 2>/dev/null | grep -c "THINK")
[ "$LOW" -eq 1 ] && pass || fail "expected level-change (high->low) to re-emit, got $LOW"
teardown_test_home

report
