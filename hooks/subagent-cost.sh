#!/usr/bin/env bash
# Claude Supercharger — Subagent Cost Tracker
# Event: SubagentStart (start) | SubagentStop (stop)
# Modes:
#   start — records agent start time asynchronously
#   stop  — calculates cost, logs to JSONL, updates session-cost, injects summary

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

MODE="${1:-start}"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

# ── Start (SubagentStart) ─────────────────────────────────────────────────────
if [[ "$MODE" == "start" ]]; then
  _INPUT=$(cat)

  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  init_hook_suppress "$PROJECT_DIR"

  AGENT_ID=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('agent_id', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  [ -z "$AGENT_ID" ] && AGENT_ID="unknown-$$"

  AGENT_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('agent_name', '') or d.get('name', '') or 'agent')
except Exception:
    print('agent')
" 2>/dev/null || echo "agent")

  NOW=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  ACTIVE_FILE="$SCOPE_DIR/.subagent-active-${AGENT_ID}"
  printf '{"agent_id":"%s","name":"%s","started_at":"%s"}\n' "$AGENT_ID" "$AGENT_NAME" "$NOW" > "$ACTIVE_FILE"

  echo "[Supercharger] subagent-cost: start recorded for agent=$AGENT_ID name=$AGENT_NAME" >&2
  exit 0
fi

# ── Stop (SubagentStop) ───────────────────────────────────────────────────────
if [[ "$MODE" == "stop" ]]; then
  _INPUT=$(cat)

  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cwd', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  init_hook_suppress "$PROJECT_DIR"

  AGENT_ID=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('agent_id', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  [ -z "$AGENT_ID" ] && AGENT_ID="unknown"

  AGENT_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('agent_name', '') or d.get('name', '') or 'agent')
except Exception:
    print('agent')
" 2>/dev/null || echo "agent")

  SESSION_ID=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  [ -z "$SESSION_ID" ] && SESSION_ID="default"

  # Extract usage tokens
  USAGE_INPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    u = d.get('usage') or {}
    print(int(u.get('input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  USAGE_CACHE_WRITE=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    u = d.get('usage') or {}
    print(int(u.get('cache_creation_input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  USAGE_CACHE_READ=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    u = d.get('usage') or {}
    print(int(u.get('cache_read_input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  USAGE_OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    u = d.get('usage') or {}
    print(int(u.get('output_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  # Read start record, calculate duration
  ACTIVE_FILE="$SCOPE_DIR/.subagent-active-${AGENT_ID}"
  STARTED_AT=""
  if [ -f "$ACTIVE_FILE" ]; then
    STARTED_AT=$(python3 -c "
import json
try:
    with open('$ACTIVE_FILE') as f:
        d = json.load(f)
    print(d.get('started_at', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
    # Also get name from start record if not in stop payload
    if [ "$AGENT_NAME" = "agent" ]; then
      AGENT_NAME=$(python3 -c "
import json
try:
    with open('$ACTIVE_FILE') as f:
        d = json.load(f)
    print(d.get('name', 'agent') or 'agent')
except Exception:
    print('agent')
" 2>/dev/null || echo "agent")
    fi
  fi

  NOW=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  DURATION_S=0
  if [ -n "$STARTED_AT" ]; then
    DURATION_S=$(python3 -c "
from datetime import datetime, timezone
try:
    started = datetime.fromisoformat('$STARTED_AT'.replace('Z','+00:00'))
    now = datetime.fromisoformat('$NOW'.replace('Z','+00:00'))
    diff = (now - started).total_seconds()
    print(int(max(0, diff)))
except Exception:
    print(0)
" 2>/dev/null || echo "0")
  fi

  # Calculate cost
  TURN_COST=$(python3 -c "
input_tok = $USAGE_INPUT
cache_write = $USAGE_CACHE_WRITE
cache_read = $USAGE_CACHE_READ
output_tok = $USAGE_OUTPUT
cost = (input_tok * 3.00 + cache_write * 3.75 + cache_read * 0.30 + output_tok * 15.00) / 1_000_000
print(f'{cost:.8f}')
" 2>/dev/null || echo "0")

  TOTAL_TOKENS=$((USAGE_INPUT + USAGE_CACHE_WRITE + USAGE_CACHE_READ + USAGE_OUTPUT))

  # Format tokens
  TOKENS_FMT=$(python3 -c "
n = $TOTAL_TOKENS
if n >= 1_000_000:
    print(f'{n/1_000_000:.1f}M')
elif n >= 1_000:
    print(f'{n/1_000:.0f}K')
else:
    print(str(n))
" 2>/dev/null || echo "${TOTAL_TOKENS}")

  # Format cost display
  COST_FMT=$(python3 -c "print(f'\${float(\"$TURN_COST\"):.2f}')" 2>/dev/null || echo "\$0.00")

  # Delete start record
  rm -f "$ACTIVE_FILE" 2>/dev/null || true

  # Append to JSONL log
  JSONL_FILE="$SCOPE_DIR/.subagent-costs-${SESSION_ID}.jsonl"
  JSONL_ENTRY=$(python3 -c "
import json
entry = {
    'agent_id': '$AGENT_ID',
    'agent_name': '$AGENT_NAME',
    'session_id': '$SESSION_ID',
    'started_at': '$STARTED_AT',
    'stopped_at': '$NOW',
    'duration_s': $DURATION_S,
    'input_tokens': $USAGE_INPUT,
    'cache_write_tokens': $USAGE_CACHE_WRITE,
    'cache_read_tokens': $USAGE_CACHE_READ,
    'output_tokens': $USAGE_OUTPUT,
    'total_tokens': $TOTAL_TOKENS,
    'cost_usd': float('$TURN_COST')
}
print(json.dumps(entry))
" 2>/dev/null || echo "{}")
  printf '%s\n' "$JSONL_ENTRY" >> "$JSONL_FILE"

  # Update .session-cost atomically
  COST_FILE="$SCOPE_DIR/.session-cost"
  COST_TMP="$SCOPE_DIR/.session-cost.tmp"
  COST_INPUT="$COST_FILE" TURN_COST="$TURN_COST" NOW="$NOW" python3 << 'PYEOF' > "$COST_TMP"
import json, os

cost_file = os.environ['COST_INPUT']
turn_cost = float(os.environ['TURN_COST'])
now = os.environ['NOW']

state = {}
if os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            state = json.load(f)
    except Exception:
        state = {}

prev_total = float(state.get('total_usd', 0) or 0)
prev_turns = int(state.get('turn_count', 0) or 0)
prev_subagent = float(state.get('subagent_total', 0) or 0)
first_updated = state.get('first_updated', '')

new_total = prev_total + turn_cost
new_subagent = prev_subagent + turn_cost
new_turns = prev_turns
avg = new_total / new_turns if new_turns > 0 else 0.0

if not first_updated:
    first_updated = now

result = {
    'total_usd': round(new_total, 8),
    'turn_count': new_turns,
    'avg_per_turn': round(avg, 8),
    'first_updated': first_updated,
    'last_updated': now,
    'subagent_total': round(new_subagent, 8)
}
print(json.dumps(result))
PYEOF
  mv "$COST_TMP" "$COST_FILE"

  # Build injection summary
  SUMMARY="[AGENT] ${AGENT_NAME} completed: ~${COST_FMT} (${TOKENS_FMT} tokens, ${DURATION_S}s)"

  echo "[Supercharger] subagent-cost: stop recorded agent=$AGENT_ID cost=$TURN_COST duration=${DURATION_S}s" >&2

  CONTEXT_JSON=$(printf '%s' "$SUMMARY" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$SUMMARY")
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}\n' "$CONTEXT_JSON"
  exit 0
fi

exit 0
