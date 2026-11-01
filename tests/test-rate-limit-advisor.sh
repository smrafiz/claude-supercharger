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

# v2.21.13: the python reads os.environ['SCOPE_DIR'] but bash never set it, so
# under the plugin runtime it fell back to ~/.claude and never found the
# session-cost file (advisor silently never fired). And the dedup file was
# global, so one session's warn suppressed another's within the same band.
begin_test "rate-limit-advisor: bash exports SCOPE_DIR to the python"
grep -q 'SCOPE_DIR="\${SUPERCHARGER_STATE' "$HOOK" && pass || fail "SCOPE_DIR not exported to python (plugin-runtime path bug)"

begin_test "rate-limit-advisor: warn-dedup file is session-scoped"
grep -q "rate-limit-last-warn-' + _sid" "$HOOK" && pass || fail "warn file not session-scoped (cross-session dedup leak)"

# Weekly window: accounts without a 5-hour limit get only seven_day, which the
# advisor never read. Thresholds 90 and 95, each once per weekly window.
_wk() { # pct [resets_at] [session] -> hook output, in the current test HOME
  printf '{"session_id":"%s","rate_limits":{"seven_day":{"used_percentage":%s,"resets_at":%s}}}' \
    "${3:-wk1}" "$1" "${2:-1900000000}" \
    | SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$HOOK" 2>/dev/null
}

begin_test "weekly: no warning below 90%"
setup_test_home; mkdir -p "$HOME/.claude/supercharger/scope"
OUT=$(_wk 88); teardown_test_home
[ -z "$OUT" ] && pass || fail "warned at 88%: $OUT"

begin_test "weekly: warns at 90%"
setup_test_home; mkdir -p "$HOME/.claude/supercharger/scope"
OUT=$(_wk 91)
case "$OUT" in *"Weekly limit 91% used"*) pass ;; *) fail "got: $OUT" ;; esac

begin_test "weekly: 90% warning shows once, even from another session"
OUT=$(_wk 92 1900000000 wk2)
[ -z "$OUT" ] && pass || fail "repeated: $OUT"

begin_test "weekly: 95% gives a second, firmer warning"
OUT=$(_wk 96)
case "$OUT" in *"Weekly limit 96% used: work may stop"*) pass ;; *) fail "got: $OUT" ;; esac

begin_test "weekly: a new weekly window warns again"
OUT=$(_wk 91 1900600000); teardown_test_home
case "$OUT" in *"Weekly limit 91% used"*) pass ;; *) fail "got: $OUT" ;; esac

begin_test "both windows: 5-hour pace warning and weekly warning together"
setup_test_home; SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TEN_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-600)))")
echo "{\"first_updated\":\"$TEN_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"
OUT=$(printf '%s' '{"session_id":"wk3","rate_limits":{"five_hour":{"used_percentage":60},"seven_day":{"used_percentage":93,"resets_at":1900000000}}}' \
  | SUPERCHARGER_STATE="$HOME/.claude/supercharger" bash "$HOOK" 2>/dev/null); teardown_test_home
case "$OUT" in *"session exhausts"*"Weekly limit 93% used"*) pass ;; *) fail "got: $OUT" ;; esac

report
