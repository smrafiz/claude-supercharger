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

# Read project dir from stdin cwd field via jq
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

init_hook_suppress "$PROJECT_DIR"

# Find .supercharger.json by walking up from PROJECT_DIR
SUPERCHARGER_JSON=""
SEARCH_DIR="$PROJECT_DIR"
for _ in 1 2 3 4 5; do
  if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
    SUPERCHARGER_JSON="$SEARCH_DIR/.supercharger.json"
    break
  fi
  PARENT=$(dirname "$SEARCH_DIR")
  [ "$PARENT" = "$SEARCH_DIR" ] && break
  SEARCH_DIR="$PARENT"
done

# Single Python block: read .session-cost, read .supercharger.json, compute forecast
RESULT=$(python3 -c "
import json, sys

cost_file = '$COST_FILE'
supercharger_json = '$SUPERCHARGER_JSON'

try:
    with open(cost_file) as f:
        d = json.load(f)
    avg = float(d.get('avg_per_turn', 0) or 0)
except Exception:
    avg = 0.0

if avg <= 0:
    sys.exit(1)

turns = 10
if supercharger_json:
    try:
        with open(supercharger_json) as f:
            cfg = json.load(f)
        v = cfg.get('forecastTurnsPerAgent', 10)
        turns = int(v) if v else 10
    except Exception:
        pass

est = avg * turns
if est < 0.10:
    sys.exit(1)

print(f'{avg:.2f}')
print(str(turns))
print(f'{est:.2f}')
" 2>/dev/null) || exit 0

AVG_FMT=$(printf '%s\n' "$RESULT" | sed -n '1p')
FORECAST_TURNS=$(printf '%s\n' "$RESULT" | sed -n '2p')
ESTIMATE=$(printf '%s\n' "$RESULT" | sed -n '3p')

MSG="[COST] Est. ~\$$ESTIMATE for this agent (avg \$$AVG_FMT/turn × ~$FORECAST_TURNS turns)"

$HOOK_SUPPRESS || echo "[Supercharger] cost-forecast: $MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
exit 0
