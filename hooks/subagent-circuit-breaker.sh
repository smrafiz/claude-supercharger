#!/usr/bin/env bash
# Claude Supercharger — Subagent Circuit Breaker (OWASP ASI08: Cascading Failures)
# Event: SubagentStart | Matcher: (none)
# Tracks subagent spawns in a rolling time window per session. Warns when the
# spawn rate suggests a runaway orchestration loop, and hard-denies past an
# extreme cap (clear runaway — fan-out recursion, retry storm, or a poisoned
# plan that keeps re-spawning workers). Defaults are deliberately high so normal
# multi-agent workflows pass untouched; tune with SC_SUBAGENT_WARN / SC_SUBAGENT_MAX.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-timing.sh"

_INPUT=$(cat)

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

RESULT=$(HOOK_INPUT="$_INPUT" SCOPE_DIR="$SCOPE_DIR" \
         WARN="${SC_SUBAGENT_WARN:-20}" MAXN="${SC_SUBAGENT_MAX:-50}" WINDOW="${SC_SUBAGENT_WINDOW:-300}" \
         python3 <<'PYEOF' 2>/dev/null
import json, os, sys
from datetime import datetime, timezone

raw = os.environ.get('HOOK_INPUT', '')
scope_dir = os.environ.get('SCOPE_DIR', '')
try:
    warn_n = int(os.environ.get('WARN', '20'))
    max_n  = int(os.environ.get('MAXN', '50'))
    window = int(os.environ.get('WINDOW', '300'))
except Exception:
    warn_n, max_n, window = 20, 50, 300

try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)

session_id = (d.get('session_id') or '') or 'default'
# sanitize for filename
session_id = ''.join(c for c in session_id if c.isalnum() or c in '-_') or 'default'

now = datetime.now(timezone.utc).timestamp()
state_file = os.path.join(scope_dir, f'.subagent-spawns-{session_id}.json')

spawns = []
if os.path.isfile(state_file):
    try:
        with open(state_file) as f:
            spawns = json.load(f)
        if not isinstance(spawns, list):
            spawns = []
    except Exception:
        spawns = []

# Drop timestamps outside the rolling window, then record this spawn.
spawns = [t for t in spawns if isinstance(t, (int, float)) and (now - t) <= window]
spawns.append(now)

# Cap stored history so the file can't grow unbounded under a real storm.
if len(spawns) > max_n + 50:
    spawns = spawns[-(max_n + 50):]

try:
    tmp = state_file + f'.{os.getpid()}.tmp'
    with open(tmp, 'w') as f:
        json.dump(spawns, f)
    os.rename(tmp, state_file)
except Exception:
    pass

count = len(spawns)
mins = max(1, window // 60)

if count >= max_n:
    print('DENY')
    print(
        f'[SECURITY] Subagent circuit breaker tripped: {count} subagent spawns in '
        f'the last {mins} min (cap {max_n}). This is a runaway fan-out / recursion '
        'pattern (OWASP ASI08 cascading failure). The spawn was blocked. Stop, '
        'inspect the orchestration loop, and re-run deliberately. Raise the cap '
        'with SC_SUBAGENT_MAX if this is intentional large-scale work.'
    )
elif count == warn_n:
    print('WARN')
    print(
        f'[NOTICE] {count} subagent spawns in the last {mins} min — approaching the '
        f'runaway cap ({max_n}). If this is an intentional large fan-out, fine; if '
        'not, check for a spawn loop before it trips the breaker.'
    )
PYEOF
)

if [ -z "$RESULT" ]; then
  exit 0
fi

VERDICT=$(printf '%s\n' "$RESULT" | sed -n '1p')
MSG=$(printf '%s\n' "$RESULT" | sed -n '2,$p')

if [ "$VERDICT" = "DENY" ]; then
  RSN=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$MSG")
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] subagent-circuit-breaker: TRIPPED — denied runaway spawn" >&2
  exit 2
fi

if [ "$VERDICT" = "WARN" ]; then
  CTX=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$MSG")
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":%s}}\n' "$CTX"
  echo "[Supercharger] subagent-circuit-breaker: warn at threshold" >&2
fi

exit 0
