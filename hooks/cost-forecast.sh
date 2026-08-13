#!/usr/bin/env bash
# Claude Supercharger — Cost Forecast
# Event: PreToolUse | Matcher: Agent
# Estimates cost before an agent spawns, based on avg_per_turn from .session-cost

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

SUPERCHARGER_DIR="$SUPERCHARGER_STATE"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
COST_FILE="$SCOPE_DIR/.session-cost"

# Skip if no session-cost file
if [ ! -f "$COST_FILE" ]; then
  exit 0
fi

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Read project dir from stdin cwd field via jq
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

# v2.6.36: resolve to main worktree root if PROJECT_DIR is a linked worktree —
# .supercharger.json lives in the main repo, not the linked checkout.
PROJECT_ROOT=$(_resolve_project_root "$PROJECT_DIR")

init_hook_suppress "$PROJECT_DIR"

# v2.6.29: one python3 fork does .session-cost read + 5-level .supercharger.json
# walk + forecast compute + JSON wrap. Was: bash for-loop walk + 2 python3 forks
# (compute, JSON wrap). Now: 1 python3. Median 80ms → 40ms (-50%).
OUT=$(COST_FILE="$COST_FILE" PROJECT_DIR="$PROJECT_ROOT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys

cost_file = os.environ['COST_FILE']
project_dir = os.environ['PROJECT_DIR']

# .session-cost
try:
    with open(cost_file) as f:
        d = json.load(f)
    avg = float(d.get('avg_per_turn', 0) or 0)
except Exception:
    avg = 0.0

if avg <= 0:
    sys.exit(0)

# Walk up 5 levels for .supercharger.json
turns = 10
search = project_dir
for _ in range(5):
    candidate = os.path.join(search, '.supercharger.json')
    if os.path.isfile(candidate):
        try:
            with open(candidate) as f:
                cfg = json.load(f)
            v = cfg.get('forecastTurnsPerAgent', 10)
            turns = int(v) if v else 10
        except Exception:
            pass
        break
    parent = os.path.dirname(search)
    if parent == search:
        break
    search = parent

est = avg * turns
if est < 0.10:
    sys.exit(0)

msg = f'[COST] Est. ~${est:.2f} for this agent (avg ${avg:.2f}/turn × ~{turns} turns)'
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': msg}}))
print(msg, file=sys.stderr)
PYEOF
)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
exit 0
