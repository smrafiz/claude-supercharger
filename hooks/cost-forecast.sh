#!/usr/bin/env bash
# Claude Supercharger — Cost Forecast
# Event: PreToolUse | Matcher: Agent
# Estimates cost before an agent spawns, based on avg_per_turn from .session-cost

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
COST_FILE="$SCOPE_DIR/.session-cost"

# Skip if no session-cost file
if [ ! -f "$COST_FILE" ]; then
  exit 0
fi

_INPUT=$(cat)

# Read avg_per_turn from .session-cost
AVG_PER_TURN=$(python3 -c "
import json
try:
    with open('$COST_FILE') as f:
        d = json.load(f)
    print(str(d.get('avg_per_turn', 0) or 0))
except Exception:
    print('0')
" 2>/dev/null || echo "0")

# Skip if avg_per_turn is 0
if python3 -c "import sys; sys.exit(0 if float('$AVG_PER_TURN') > 0 else 1)" 2>/dev/null; then
  : # continue
else
  exit 0
fi

# Read project dir from stdin cwd field
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('cwd', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

init_hook_suppress "$PROJECT_DIR"

# Read forecastTurnsPerAgent from .supercharger.json (default: 10)
FORECAST_TURNS=10
SEARCH_DIR="$PROJECT_DIR"
for _ in 1 2 3 4 5; do
  if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
    FORECAST_TURNS=$(python3 -c "
import json
try:
    with open('$SEARCH_DIR/.supercharger.json') as f:
        d = json.load(f)
    v = d.get('forecastTurnsPerAgent', 10)
    print(int(v) if v else 10)
except Exception:
    print(10)
" 2>/dev/null || echo "10")
    break
  fi
  PARENT=$(dirname "$SEARCH_DIR")
  [ "$PARENT" = "$SEARCH_DIR" ] && break
  SEARCH_DIR="$PARENT"
done

# Calculate estimated cost
ESTIMATE=$(python3 -c "
avg = float('$AVG_PER_TURN')
turns = int('$FORECAST_TURNS')
est = avg * turns
print(f'{est:.2f}')
" 2>/dev/null || echo "0.00")

# Skip if estimated cost < $0.10
if python3 -c "import sys; sys.exit(0 if float('$ESTIMATE') >= 0.10 else 1)" 2>/dev/null; then
  : # continue
else
  exit 0
fi

# Build advisory message
AVG_FMT=$(python3 -c "print(f'{float(\"$AVG_PER_TURN\"):.2f}')" 2>/dev/null || echo "$AVG_PER_TURN")
MSG="[COST] Est. ~\$$ESTIMATE for this agent (avg \$$AVG_FMT/turn × ~$FORECAST_TURNS turns)"

$HOOK_SUPPRESS || echo "[Supercharger] cost-forecast: $MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
exit 0
