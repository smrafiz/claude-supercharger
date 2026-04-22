#!/usr/bin/env bash
# Claude Supercharger — Budget Cap Hook
# Modes:
#   (no arg)  — PostToolUse accumulator: reads token usage, calculates cost, writes .session-cost
#   check     — PreToolUse blocker: reads .session-cost, warns at 80%, blocks at 100%

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

MODE="${1:-accumulate}"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

COST_FILE="$SCOPE_DIR/.session-cost"
COST_TMP="$SCOPE_DIR/.session-cost.tmp"

# ── accumulate (PostToolUse) ───────────────────────────────────────────────────
if [[ "$MODE" == "accumulate" ]]; then
  _INPUT=$(cat)

  # Extract usage from PostToolUse payload
  USAGE_INPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # PostToolUse: usage is in tool_response or usage field
    usage = data.get('usage') or (data.get('tool_response') or {}).get('usage') or data.get('tool_response') or {}
    if not isinstance(usage, dict):
        usage = {}
    print(int(usage.get('input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  USAGE_CACHE_WRITE=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    usage = data.get('usage') or (data.get('tool_response') or {}).get('usage') or data.get('tool_response') or {}
    if not isinstance(usage, dict):
        usage = {}
    print(int(usage.get('cache_creation_input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  USAGE_CACHE_READ=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    usage = data.get('usage') or (data.get('tool_response') or {}).get('usage') or data.get('tool_response') or {}
    if not isinstance(usage, dict):
        usage = {}
    print(int(usage.get('cache_read_input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  USAGE_OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    usage = data.get('usage') or (data.get('tool_response') or {}).get('usage') or data.get('tool_response') or {}
    if not isinstance(usage, dict):
        usage = {}
    print(int(usage.get('output_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

  # If all zero, nothing to accumulate — exit cleanly
  TOTAL_TOKENS=$((USAGE_INPUT + USAGE_CACHE_WRITE + USAGE_CACHE_READ + USAGE_OUTPUT))
  if [ "$TOTAL_TOKENS" -eq 0 ]; then
    echo "[Supercharger] budget-cap: no usage data in payload — skipping" >&2
    exit 0
  fi

  # Calculate turn cost using pricing table
  # input: $3.00/MTok, cache_write: $3.75/MTok, cache_read: $0.30/MTok, output: $15.00/MTok
  TURN_COST=$(python3 -c "
input_tok = $USAGE_INPUT
cache_write = $USAGE_CACHE_WRITE
cache_read = $USAGE_CACHE_READ
output_tok = $USAGE_OUTPUT
cost = (input_tok * 3.00 + cache_write * 3.75 + cache_read * 0.30 + output_tok * 15.00) / 1_000_000
print(f'{cost:.8f}')
" 2>/dev/null || echo "0")

  # Read existing state or start fresh
  NOW=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  COST_INPUT="$COST_FILE" TURN_COST="$TURN_COST" NOW="$NOW" python3 << 'PYEOF' > "$COST_TMP"
import json, os

cost_file = os.environ['COST_INPUT']
turn_cost = float(os.environ['TURN_COST'])
now = os.environ['NOW']

# Load existing state
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
new_turns = prev_turns + 1
avg = new_total / new_turns if new_turns > 0 else 0.0

if not first_updated:
    first_updated = now

result = {
    'total_usd': round(new_total, 8),
    'turn_count': new_turns,
    'avg_per_turn': round(avg, 8),
    'first_updated': first_updated,
    'last_updated': now,
    'subagent_total': round(prev_subagent, 8)
}
print(json.dumps(result))
PYEOF

  # Atomic move
  mv "$COST_TMP" "$COST_FILE"

  echo "[Supercharger] budget-cap: accumulated turn_cost=${TURN_COST} file=$COST_FILE" >&2
  exit 0
fi

# ── check (PreToolUse) ────────────────────────────────────────────────────────
if [[ "$MODE" == "check" ]]; then
  _INPUT=$(cat)

  # Extract tool_name for read-only bypass
  TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  if [ -z "$TOOL_NAME" ]; then
    TOOL_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
  fi

  # Resolve cap: env var > .supercharger.json > no cap
  CAP=""
  if [ -n "${SESSION_BUDGET_CAP:-}" ]; then
    CAP="$SESSION_BUDGET_CAP"
  else
    # Walk up from cwd to find .supercharger.json
    PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
    SEARCH_DIR="$PROJECT_DIR"
    for _ in 1 2 3 4 5; do
      if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
        CAP=$(python3 -c "
import json
try:
    with open('$SEARCH_DIR/.supercharger.json') as f:
        d = json.load(f)
    b = d.get('budget', '')
    print(str(b) if b else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
        break
      fi
      PARENT=$(dirname "$SEARCH_DIR")
      [ "$PARENT" = "$SEARCH_DIR" ] && break
      SEARCH_DIR="$PARENT"
    done
  fi

  # No cap configured — passthrough
  if [ -z "$CAP" ]; then
    exit 0
  fi

  # Read current spend
  CURRENT_SPEND="0"
  if [ -f "$COST_FILE" ]; then
    CURRENT_SPEND=$(python3 -c "
import json
try:
    with open('$COST_FILE') as f:
        d = json.load(f)
    print(str(d.get('total_usd', 0) or 0))
except Exception:
    print('0')
" 2>/dev/null || echo "0")
  fi

  # Evaluate thresholds
  DECISION=$(CAP="$CAP" SPEND="$CURRENT_SPEND" TOOL="$TOOL_NAME" python3 << 'PYEOF'
import os

cap = float(os.environ['CAP'])
spend = float(os.environ['SPEND'])
tool = os.environ.get('TOOL', '')

READ_ONLY_TOOLS = {'Read', 'Glob', 'Grep'}

pct = (spend / cap * 100) if cap > 0 else 0

if pct >= 100:
    # Over cap — check if read-only bypass applies
    if tool in READ_ONLY_TOOLS:
        print('pass')
    else:
        reason = f"Session budget cap reached: ${spend:.4f} spent of ${cap:.2f} cap ({pct:.0f}%). Use read-only tools or start a new session."
        print(f'block:{reason}')
elif pct >= 80:
    msg = f"[BUDGET] {pct:.0f}% of session cap used (${spend:.4f} / ${cap:.2f}). Consider wrapping up."
    print(f'warn:{msg}')
else:
    print('pass')
PYEOF
)

  if [[ "$DECISION" == "pass" ]]; then
    exit 0
  elif [[ "$DECISION" == warn:* ]]; then
    MSG="${DECISION#warn:}"
    echo "[Supercharger] budget-cap: warning — $MSG" >&2
    CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$MSG")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
    exit 0
  elif [[ "$DECISION" == block:* ]]; then
    REASON="${DECISION#block:}"
    echo "[Supercharger] budget-cap: BLOCKING — $REASON" >&2
    REASON_JSON=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$REASON")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$REASON_JSON"
    exit 2
  fi

  exit 0
fi

exit 0
