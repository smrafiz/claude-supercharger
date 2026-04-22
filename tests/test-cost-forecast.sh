#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/cost-forecast.sh"

echo "=== Cost Forecast Tests ==="

# ── Test 1: estimates cost for Agent tool call ─────────────────────────────────
begin_test "estimates cost for Agent tool call"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

printf '{"total_usd":1.90,"turn_count":10,"avg_per_turn":0.19,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Agent","cwd":"/tmp"}'
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?
if [ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -qi "COST"; then
  pass
else
  fail "expected exit 0 + COST in output (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

# ── Test 2: skips when no session-cost data ────────────────────────────────────
begin_test "skips when no session-cost data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# no .session-cost file written

PAYLOAD='{"tool_name":"Agent","cwd":"/tmp"}'
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?
if [ "$EXIT" -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass
else
  fail "expected exit 0 + no output (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

# ── Test 3: skips when avg_per_turn is 0 ──────────────────────────────────────
begin_test "skips when avg_per_turn is 0"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

printf '{"total_usd":0,"turn_count":0,"avg_per_turn":0,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Agent","cwd":"/tmp"}'
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?
if [ "$EXIT" -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass
else
  fail "expected exit 0 + no output (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

# ── Test 4: skips when estimated cost < 0.10 ──────────────────────────────────
begin_test "skips when estimated cost < 0.10"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# avg=0.001, turns=10 → estimate=0.01 < 0.10 → skip
printf '{"total_usd":0.01,"turn_count":10,"avg_per_turn":0.001,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

PAYLOAD='{"tool_name":"Agent","cwd":"/tmp"}'
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?
if [ "$EXIT" -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass
else
  fail "expected exit 0 + no output (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

# ── Test 5: uses forecastTurnsPerAgent from config ────────────────────────────
begin_test "uses forecastTurnsPerAgent from config"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

printf '{"total_usd":2.50,"turn_count":5,"avg_per_turn":0.50,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"

# Create a temp project dir with .supercharger.json
PROJECT_TMP=$(mktemp -d)
printf '{"forecastTurnsPerAgent":5}' > "$PROJECT_TMP/.supercharger.json"

PAYLOAD="{\"tool_name\":\"Agent\",\"cwd\":\"$PROJECT_TMP\"}"
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
EXIT=$?
rm -rf "$PROJECT_TMP"

if [ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "2.50"; then
  pass
else
  fail "expected exit 0 + '2.50' in output (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home

report
