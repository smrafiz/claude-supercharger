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

report
