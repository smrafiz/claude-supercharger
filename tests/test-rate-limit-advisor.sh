#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/rate-limit-advisor.sh"

echo "=== Rate Limit Advisor Tests ==="

# Test 1: warns when projected exhaustion < 30m
begin_test "warns when projected exhaustion < 30m"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

TEN_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-600)))")
echo "{\"total_usd\":0.5,\"turn_count\":5,\"avg_per_turn\":0.1,\"first_updated\":\"$TEN_MIN_AGO\",\"last_updated\":\"$TEN_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"

# 60% used in 10 min → burn = 6%/min → time_to_exhaust = 40/6 ≈ 6.7m < 30m → WARN
PAYLOAD='{"rate_limits":{"five_hour":{"used_percentage":60}}}'
OUTPUT=$(SCOPE_DIR="$SCOPE_DIR" echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -q "RATE"; then
  pass
else
  fail "expected RATE in output, got: $OUTPUT"
fi
teardown_test_home

# Test 2: no warning when exhaustion > 30m
begin_test "no warning when exhaustion > 30m"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

SIXTY_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-3600)))")
echo "{\"total_usd\":0.5,\"turn_count\":5,\"avg_per_turn\":0.1,\"first_updated\":\"$SIXTY_MIN_AGO\",\"last_updated\":\"$SIXTY_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"

# 10% used in 60 min → burn = 0.167%/min → time_to_exhaust = 90/0.167 ≈ 540m > 30m → no warn
PAYLOAD='{"rate_limits":{"five_hour":{"used_percentage":10}}}'
OUTPUT=$(SCOPE_DIR="$SCOPE_DIR" echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -q "RATE"; then
  fail "expected no RATE warning, got: $OUTPUT"
else
  pass
fi
teardown_test_home

# Test 3: no warning when no rate limit data
begin_test "no warning when no rate limit data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

PAYLOAD='{}'
OUTPUT=$(SCOPE_DIR="$SCOPE_DIR" echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -q "RATE"; then
  fail "expected no RATE warning on empty data, got: $OUTPUT"
else
  pass
fi
teardown_test_home

# Test 4: deduplicates within same 10m band
begin_test "deduplicates within same 10m band"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

TEN_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-600)))")
echo "{\"total_usd\":0.5,\"turn_count\":5,\"avg_per_turn\":0.1,\"first_updated\":\"$TEN_MIN_AGO\",\"last_updated\":\"$TEN_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"rate_limits":{"five_hour":{"used_percentage":60}}}'

# First call — should warn
OUTPUT1=$(SCOPE_DIR="$SCOPE_DIR" echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
# Second call — same band, should be silent
OUTPUT2=$(SCOPE_DIR="$SCOPE_DIR" echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)

if echo "$OUTPUT1" | grep -q "RATE" && ! echo "$OUTPUT2" | grep -q "RATE"; then
  pass
else
  fail "expected first call to warn and second to be silent. first='$OUTPUT1' second='$OUTPUT2'"
fi
teardown_test_home

report
