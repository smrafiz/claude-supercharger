#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/cache-health.sh"

echo "=== Cache Health Monitor Tests ==="

# ── Test 1: Healthy cache (>70%) produces no output ──────────────────────────

begin_test "healthy cache (>70%) produces no output"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Seed counter so next call is the 5th (counter will become 5 → 5%5==0)
printf '4\n' > "$SCOPE_DIR/.cache-health-counter"

# 90% hit rate: cache_read=900, cache_creation=100
PAYLOAD='{"tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":900,"cache_creation_input_tokens":100}}}'
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?

if [ "$EXIT" -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass
else
  fail "expected exit 0 and no output for healthy cache (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

# ── Test 2: Degraded cache (<50% for 3 readings) triggers warning ─────────────

begin_test "degraded cache (<50% for 3 readings) triggers warning"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# 30% hit rate: cache_read=30, cache_creation=70
BAD_PAYLOAD='{"tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":30,"cache_creation_input_tokens":70}}}'

# Round 1: seed counter to 4, send 1 call → becomes 5th call
printf '4\n' > "$SCOPE_DIR/.cache-health-counter"
echo "$BAD_PAYLOAD" | bash "$HOOK" >/dev/null 2>&1

# Round 2: seed counter to 9, send 1 call → becomes 10th call
printf '9\n' > "$SCOPE_DIR/.cache-health-counter"
echo "$BAD_PAYLOAD" | bash "$HOOK" >/dev/null 2>&1

# Round 3: seed counter to 14, send 1 call → becomes 15th call (should warn)
printf '14\n' > "$SCOPE_DIR/.cache-health-counter"
OUTPUT=$(echo "$BAD_PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?

if [ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -qi "CACHE"; then
  pass
else
  fail "expected exit 0 and CACHE in output after 3 degraded readings (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

# ── Test 3: No usage data = no crash ─────────────────────────────────────────

begin_test "no usage data = no crash"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Counter at 4 so it will process on next call
printf '4\n' > "$SCOPE_DIR/.cache-health-counter"

PAYLOAD='{"tool_name":"Read","tool_response":{}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?

if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected exit 0 on empty tool_response, got $EXIT"
fi
teardown_test_home

# ── Test 4: Zero cache tokens = no crash ──────────────────────────────────────

begin_test "zero cache tokens = no crash"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

printf '4\n' > "$SCOPE_DIR/.cache-health-counter"

PAYLOAD='{"tool_name":"Write","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?

if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected exit 0 when both cache tokens are 0, got $EXIT"
fi
teardown_test_home

report
