#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/subagent-cost.sh"

echo "=== Subagent Cost Tracker Tests ==="

# ── Test 1: start creates active file ─────────────────────────────────────────
begin_test "start: creates active file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

PAYLOAD='{"agent_id":"abc123","agent_name":"code-helper","session_id":"sess1","cwd":"/tmp"}'
echo "$PAYLOAD" | bash "$HOOK" start >/dev/null 2>&1
EXIT=$?

ACTIVE_FILE="$SCOPE_DIR/.subagent-active-abc123"
if [ "$EXIT" -ne 0 ]; then
  fail "start exited $EXIT"
elif [ ! -f "$ACTIVE_FILE" ]; then
  fail "active file not created: $ACTIVE_FILE"
else
  CONTENT=$(cat "$ACTIVE_FILE")
  if echo "$CONTENT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('agent_id')=='abc123'" 2>/dev/null; then
    pass
  else
    fail "active file content invalid: $CONTENT"
  fi
fi
teardown_test_home

# ── Test 2: stop calculates cost and logs to JSONL ────────────────────────────
begin_test "stop: calculates cost and logs to JSONL"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Seed start record
NOW_PAST=$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=30)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"agent_id":"abc123","name":"code-helper","started_at":"%s"}\n' "$NOW_PAST" > "$SCOPE_DIR/.subagent-active-abc123"

PAYLOAD='{"agent_id":"abc123","agent_name":"code-helper","session_id":"sess1","cwd":"/tmp","usage":{"input_tokens":10000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5000}}'
echo "$PAYLOAD" | bash "$HOOK" stop >/dev/null 2>&1
EXIT=$?

JSONL_FILE="$SCOPE_DIR/.subagent-costs-sess1.jsonl"
if [ "$EXIT" -ne 0 ]; then
  fail "stop exited $EXIT"
elif [ ! -f "$JSONL_FILE" ]; then
  fail "JSONL file not created: $JSONL_FILE"
else
  HAS_AGENT=$(python3 -c "
import json
with open('$JSONL_FILE') as f:
    for line in f:
        d = json.loads(line.strip())
        if d.get('agent_id') == 'abc123':
            print('ok')
            break
" 2>/dev/null || echo "")
  if [ "$HAS_AGENT" = "ok" ]; then
    pass
  else
    fail "JSONL does not contain agent_id=abc123"
  fi
fi
teardown_test_home

# ── Test 3: stop cleans up active file ────────────────────────────────────────
begin_test "stop: cleans up active file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Seed start record
NOW_PAST=$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=10)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"agent_id":"abc123","name":"code-helper","started_at":"%s"}\n' "$NOW_PAST" > "$SCOPE_DIR/.subagent-active-abc123"

PAYLOAD='{"agent_id":"abc123","agent_name":"code-helper","session_id":"sess1","cwd":"/tmp","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500}}'
echo "$PAYLOAD" | bash "$HOOK" stop >/dev/null 2>&1

ACTIVE_FILE="$SCOPE_DIR/.subagent-active-abc123"
if [ -f "$ACTIVE_FILE" ]; then
  fail "active file not deleted after stop"
else
  pass
fi
teardown_test_home

# ── Test 4: stop updates session-cost total ───────────────────────────────────
begin_test "stop: updates session-cost total"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Seed .session-cost with total=1.00
printf '{"total_usd":1.00,"turn_count":5,"avg_per_turn":0.20,"first_updated":"2026-04-22T00:00:00Z","last_updated":"2026-04-22T00:00:00Z","subagent_total":0}\n' > "$SCOPE_DIR/.session-cost"

# Seed start record
NOW_PAST=$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=20)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"agent_id":"abc123","name":"code-helper","started_at":"%s"}\n' "$NOW_PAST" > "$SCOPE_DIR/.subagent-active-abc123"

# input: 10000*3.00/1M = 0.03 → new total > 1.00
PAYLOAD='{"agent_id":"abc123","agent_name":"code-helper","session_id":"sess1","cwd":"/tmp","usage":{"input_tokens":10000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}'
echo "$PAYLOAD" | bash "$HOOK" stop >/dev/null 2>&1

NEW_TOTAL=$(python3 -c "
import json
with open('$SCOPE_DIR/.session-cost') as f:
    d = json.load(f)
print(d.get('total_usd', 0))
" 2>/dev/null || echo "0")

RESULT=$(python3 -c "print('ok' if float('$NEW_TOTAL') > 1.0 else 'bad')" 2>/dev/null || echo "bad")
if [ "$RESULT" = "ok" ]; then
  pass
else
  fail "expected total_usd > 1.0, got $NEW_TOTAL"
fi
teardown_test_home

# ── Test 5: stop injects agent summary ────────────────────────────────────────
begin_test "stop: injects agent summary"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Seed start record
NOW_PAST=$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=34)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"agent_id":"abc123","name":"code-helper","started_at":"%s"}\n' "$NOW_PAST" > "$SCOPE_DIR/.subagent-active-abc123"

PAYLOAD='{"agent_id":"abc123","agent_name":"code-helper","session_id":"sess1","cwd":"/tmp","usage":{"input_tokens":10000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5000}}'
OUTPUT=$(echo "$PAYLOAD" | bash "$HOOK" stop 2>/dev/null)

if echo "$OUTPUT" | grep -q "\[AGENT\]"; then
  pass
else
  fail "output does not contain [AGENT]: $OUTPUT"
fi
teardown_test_home

# ── v2.7.11: real CC 2.1.181 SubagentStop shape — agent_type (not agent_name),
# no usage in payload, tokens recovered from agent_transcript_path ─────────────
begin_test "stop: reads agent_type as name (real CC payload shape)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
PAYLOAD='{"agent_id":"x1","agent_type":"Marie Curie (Scientist)","session_id":"realshape"}'
echo "$PAYLOAD" | bash "$HOOK" stop >/dev/null 2>&1
NAME=$(tail -1 "$SCOPE_DIR/.subagent-costs-realshape.jsonl" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['agent_name'])" 2>/dev/null)
[ "$NAME" = "Marie Curie (Scientist)" ] && pass || fail "expected name from agent_type, got '$NAME'"
teardown_test_home

begin_test "stop: recovers token usage + cost from agent_transcript_path"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TRANS="$SCOPE_DIR/fake-agent-transcript.jsonl"
# Two assistant messages with usage (no usage in the stop payload itself)
{
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":3000,"output_tokens":500}}}'
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":3000,"output_tokens":500}}}'
} > "$TRANS"
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"agent_id":"x2","agent_type":"Tony Stark (Engineer)","session_id":"transcost","agent_transcript_path":sys.argv[1]}))' "$TRANS")
echo "$PAYLOAD" | bash "$HOOK" stop >/dev/null 2>&1
ENTRY=$(tail -1 "$SCOPE_DIR/.subagent-costs-transcost.jsonl" 2>/dev/null)
TOT=$(echo "$ENTRY" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_tokens'])" 2>/dev/null)
COST=$(echo "$ENTRY" | python3 -c "import sys,json; print('yes' if json.load(sys.stdin)['cost_usd']>0 else 'no')" 2>/dev/null)
# total = 2000 in + 2000 cw + 6000 cr + 1000 out = 11000
if [ "$TOT" = "11000" ] && [ "$COST" = "yes" ]; then pass
else fail "expected total=11000 cost>0, got total=$TOT cost=$COST"; fi
teardown_test_home

begin_test "start(subagent_id) → stop(agent_id) yields nonzero duration"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
# Seed the active file 5s in the past, keyed by the id stop will use, but written
# via the START payload's subagent_id key (the real CC mismatch).
echo '{"subagent_id":"dur9","subagent_type":"Sherlock Holmes (Detective)","session_id":"durses"}' | bash "$HOOK" start >/dev/null 2>&1
# Backdate the active file 5s so duration is measurable
PAST=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(seconds=5)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
python3 -c "import json; p='$SCOPE_DIR/.subagent-active-dur9'; d=json.load(open(p)); d['started_at']='$PAST'; json.dump(d,open(p,'w'))"
echo '{"agent_id":"dur9","agent_type":"Sherlock Holmes (Detective)","session_id":"durses"}' | bash "$HOOK" stop >/dev/null 2>&1
DUR=$(tail -1 "$SCOPE_DIR/.subagent-costs-durses.jsonl" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['duration_s'])" 2>/dev/null)
python3 -c "import sys; sys.exit(0 if float('$DUR' or 0)>=4 else 1)" && pass || fail "expected duration>=4s, got $DUR"
teardown_test_home

# ── v2.7.13: SubagentStop re-fires (stop_hook_active) must NOT over-count.
# Each re-fire carries the cumulative transcript total; upsert one row per
# agent_id (last wins) and add only the delta to the session aggregate. ──────
begin_test "stop: re-fires upsert one row + don't inflate session-cost"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
TRANS="$SCOPE_DIR/refire-transcript.jsonl"
mk_trans() { python3 -c '
import json,sys
n=int(sys.argv[1])
print("\n".join(json.dumps({"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1000}}}) for _ in range(n)))' "$1"; }
# Three SubagentStop firings with a GROWING transcript (1 -> 3 -> 7 messages)
for N in 1 3 7; do
  mk_trans "$N" > "$TRANS"
  PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"agent_id":"refireX","agent_type":"general-purpose","session_id":"refireses","agent_transcript_path":sys.argv[1]}))' "$TRANS")
  echo "$PAYLOAD" | bash "$HOOK" stop >/dev/null 2>&1
done
F="$SCOPE_DIR/.subagent-costs-refireses.jsonl"
ROWS=$(wc -l < "$F" 2>/dev/null | tr -d ' ')
# final cumulative = 7 messages * 2000 tok = 14000; session aggregate must equal
# the single final cost, NOT the sum of all three firings.
FINAL_TOK=$(tail -1 "$F" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_tokens'])" 2>/dev/null)
SUB=$(python3 -c "import json; print(round(json.load(open('$SCOPE_DIR/.session-cost'))['subagent_total'],6))" 2>/dev/null)
LAST_COST=$(tail -1 "$F" | python3 -c "import sys,json; print(round(json.load(sys.stdin)['cost_usd'],6))" 2>/dev/null)
if [ "$ROWS" = "1" ] && [ "$FINAL_TOK" = "14000" ] && [ "$SUB" = "$LAST_COST" ]; then pass
else fail "expected 1 row / 14000 tok / subagent_total==final ($LAST_COST); got rows=$ROWS tok=$FINAL_TOK sub=$SUB"; fi
teardown_test_home

report
