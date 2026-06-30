#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/budget-cap.sh"

echo "=== Budget Cap Tests ==="

# ── Accumulator Tests ──────────────────────────────────────────────────────────

# v2.7.15: accumulate now sources usage from the transcript (PostToolUse carries
# none). Each assistant message = one billed turn; we sum incrementally by offset.
asst_msg() { # input cw cr output -> a transcript assistant line (no model = sonnet)
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$1" "$2" "$3" "$4"
}

begin_test "accumulates cost from transcript usage data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TR="$SCOPE_DIR/transcript.jsonl"
# sonnet: 1000*3 + 500*3.75 + 2000*0.30 + 200*15 = 8475 /1M = 0.008475
asst_msg 1000 500 2000 200 > "$TR"
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","transcript_path":sys.argv[1]}))' "$TR")
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -ne 0 ]; then
  fail "accumulator exited $EXIT"
elif [ ! -f "$SCOPE_DIR/.session-cost" ]; then
  fail ".session-cost not created"
else
  TOTAL=$(python3 -c "
import json
d = json.load(open('$SCOPE_DIR/.session-cost'))
print('ok' if abs(d.get('total_usd',0) - 0.008475) < 0.000001 else f'bad:{d.get(\"total_usd\")}')
" 2>/dev/null || echo "parse-error")
  [ "$TOTAL" = "ok" ] && pass || fail "expected total≈0.008475, got $TOTAL"
fi
teardown_test_home

begin_test "accumulates incrementally across calls (one new turn per call)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TR="$SCOPE_DIR/transcript.jsonl"
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","transcript_path":sys.argv[1]}))' "$TR")
: > "$TR"
for i in 1 2 3; do
  asst_msg 1000 0 0 100 >> "$TR"       # append one new turn
  echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
done
TURN_COUNT=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost')).get('turn_count',0))" 2>/dev/null || echo 0)
[ "$TURN_COUNT" = "3" ] && pass || fail "expected turn_count=3, got $TURN_COUNT"
teardown_test_home

begin_test "computes avg_per_turn"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TR="$SCOPE_DIR/transcript.jsonl"
{ asst_msg 1000 0 0 100; asst_msg 1000 0 0 100; } > "$TR"
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","transcript_path":sys.argv[1]}))' "$TR")
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
CHECK=$(python3 -c "
import json
d = json.load(open('$SCOPE_DIR/.session-cost'))
total=d.get('total_usd',0); turns=d.get('turn_count',0); avg=d.get('avg_per_turn',0)
exp = total/turns if turns>0 else 0
print('ok' if abs(avg-exp) < 0.000001 else f'bad:{avg} vs {exp}')
" 2>/dev/null || echo "parse-error")
[ "$CHECK" = "ok" ] && pass || fail "avg_per_turn mismatch: $CHECK"
teardown_test_home

# v2.7.17: re-running on the SAME (unchanged) transcript must NOT re-sum — the
# byte offset must land exactly at EOF (binary tell()), not drift past it.
begin_test "incremental offset is exact — repeated calls don't re-count"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TR="$SCOPE_DIR/transcript.jsonl"
# include a non-ASCII char so byte length != char length (would break text-mode seek)
{ asst_msg 1000 0 0 100; printf '{"type":"user","message":{"content":"caf\xc3\xa9 \xe2\x9c\x93 unicode"}}\n'; asst_msg 1000 0 0 100; } > "$TR"
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","transcript_path":sys.argv[1]}))' "$TR")
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
M1=$(python3 -c "import json; print(round(json.load(open('$SCOPE_DIR/.session-cost'))['main_total'],8))")
T1=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['turn_count'])")
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1   # same transcript, no new lines
echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
M2=$(python3 -c "import json; print(round(json.load(open('$SCOPE_DIR/.session-cost'))['main_total'],8))")
T2=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['turn_count'])")
if [ "$M1" = "$M2" ] && [ "$T1" = "$T2" ] && [ "$T1" = "2" ]; then pass
else fail "re-counted on unchanged transcript: main $M1->$M2, turns $T1->$T2 (want stable, turns=2)"; fi
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

# v2.7.16: fcntl.flock serializes the RMW — concurrent writers on the same
# transcript count each message exactly once (no lost updates, no double-count).
begin_test "concurrent accumulate writers don't lose or double-count (flock)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TR="$SCOPE_DIR/transcript.jsonl"
# 10 assistant turns, 1000 input tokens each (sonnet $3/MTok => $0.003/turn => $0.030)
: > "$TR"
for i in $(seq 1 10); do
  printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":0}}}' >> "$TR"
done
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","transcript_path":sys.argv[1]}))' "$TR")
# fire 10 concurrent accumulators racing from offset 0
for i in $(seq 1 10); do echo "$PAYLOAD" | bash "$HOOK" >/dev/null 2>&1 & done
wait
RES=$(python3 -c "
import json
d = json.load(open('$SCOPE_DIR/.session-cost'))
print('ok' if abs(d.get('main_total',0) - 0.030) < 0.000001 and d.get('turn_count',0) == 10 else f'bad:main={d.get(\"main_total\")} turns={d.get(\"turn_count\")}')
" 2>/dev/null || echo "parse-error")
[ "$RES" = "ok" ] && pass || fail "concurrent writers miscounted: $RES (want main=0.030 turns=10)"
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
