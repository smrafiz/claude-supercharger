#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/budget-cap.sh"

echo "=== Budget Cap Tests ==="

# ── Accumulator Tests ──────────────────────────────────────────────────────────

begin_test "accumulates cost from PostToolUse usage data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# input: 1000*3.00/1M = 0.003000
# cache_write: 500*3.75/1M = 0.001875
# cache_read: 2000*0.30/1M = 0.000600
# output: 200*15.00/1M = 0.003000
# total = 0.008475
PAYLOAD='{"tool_name":"Write","usage":{"input_tokens":1000,"cache_creation_input_tokens":500,"cache_read_input_tokens":2000,"output_tokens":200}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -ne 0 ]; then
  fail "accumulator exited $EXIT"
elif [ ! -f "$SCOPE_DIR/.session-cost" ]; then
  fail ".session-cost not created"
else
  TOTAL=$(python3 -c "
import json
with open('$SCOPE_DIR/.session-cost') as f:
    d = json.load(f)
total = d.get('total_usd', 0)
# accept within 0.000001 of 0.008475
print('ok' if abs(total - 0.008475) < 0.000001 else f'bad:{total}')
" 2>/dev/null || echo "parse-error")
  if [ "$TOTAL" = "ok" ]; then
    pass
  else
    fail "expected total≈0.008475, got $TOTAL"
  fi
fi
teardown_test_home

begin_test "accumulates across multiple calls"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

PAYLOAD='{"tool_name":"Write","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1

TURN_COUNT=$(python3 -c "
import json
with open('$SCOPE_DIR/.session-cost') as f:
    d = json.load(f)
print(d.get('turn_count', 0))
" 2>/dev/null || echo "0")

if [ "$TURN_COUNT" = "3" ]; then
  pass
else
  fail "expected turn_count=3, got $TURN_COUNT"
fi
teardown_test_home

begin_test "computes avg_per_turn"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

PAYLOAD='{"tool_name":"Write","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1

CHECK=$(python3 -c "
import json
with open('$SCOPE_DIR/.session-cost') as f:
    d = json.load(f)
total = d.get('total_usd', 0)
turns = d.get('turn_count', 0)
avg = d.get('avg_per_turn', 0)
expected_avg = total / turns if turns > 0 else 0
print('ok' if abs(avg - expected_avg) < 0.000001 else f'bad:{avg} vs {expected_avg}')
" 2>/dev/null || echo "parse-error")

if [ "$CHECK" = "ok" ]; then
  pass
else
  fail "avg_per_turn mismatch: $CHECK"
fi
teardown_test_home

begin_test "handles missing usage data gracefully"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Empty tool_response with no usage fields
PAYLOAD='{"tool_name":"Read","tool_response":{}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected exit 0 on empty payload, got $EXIT"
fi
teardown_test_home

begin_test "atomic write via tmp file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

PAYLOAD='{"tool_name":"Write","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}'
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1

if [ -f "$SCOPE_DIR/.session-cost.tmp" ]; then
  fail ".session-cost.tmp lingered after accumulation"
else
  pass
fi
teardown_test_home

# ── Blocker Tests ──────────────────────────────────────────────────────────────

begin_test "no cap configured = passthrough"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Write a high cost to state
printf '{"total_usd":99.99,"turn_count":100,"avg_per_turn":1.0,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Write","cwd":"/tmp"}'
EXIT=$(echo "$PAYLOAD" | unset SESSION_BUDGET_CAP; env -u SESSION_BUDGET_CAP bash "$HOOK" check >/dev/null 2>&1; echo $?)
if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected exit 0 (no cap), got $EXIT"
fi
teardown_test_home

begin_test "under 80% = passthrough"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# $3.00 spent with $5.00 cap = 60% → passthrough
printf '{"total_usd":3.00,"turn_count":10,"avg_per_turn":0.30,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Write","cwd":"/tmp"}'
echo "$PAYLOAD" | SESSION_BUDGET_CAP=5.00 bash "$HOOK" check >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected exit 0 (under 80%), got $EXIT"
fi
teardown_test_home

begin_test "at 80% = warn (exit 0)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# $4.10 spent with $5.00 cap = 82% → warn
printf '{"total_usd":4.10,"turn_count":10,"avg_per_turn":0.41,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Write","cwd":"/tmp"}'
OUTPUT=$(echo "$PAYLOAD" | SESSION_BUDGET_CAP=5.00 bash "$HOOK" check 2>/dev/null)
EXIT=$?
if [ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -qi "BUDGET"; then
  pass
else
  fail "expected exit 0 + BUDGET in output (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

begin_test "at 100% = block (exit 2)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# $5.50 spent with $5.00 cap = 110% → block
printf '{"total_usd":5.50,"turn_count":10,"avg_per_turn":0.55,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Write","cwd":"/tmp"}'
echo "$PAYLOAD" | SESSION_BUDGET_CAP=5.00 bash "$HOOK" check >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 2 ]; then
  pass
else
  fail "expected exit 2 (blocked), got $EXIT"
fi
teardown_test_home

begin_test "read-only tools bypass block"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Over cap
printf '{"total_usd":6.00,"turn_count":10,"avg_per_turn":0.60,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Read","cwd":"/tmp"}'
echo "$PAYLOAD" | SESSION_BUDGET_CAP=5.00 bash "$HOOK" check >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected exit 0 for Read tool bypass, got $EXIT"
fi
teardown_test_home

report
