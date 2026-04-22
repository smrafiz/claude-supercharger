#!/usr/bin/env bash
# Claude Supercharger — Rate Limit Burn Advisor
# Event: UserPromptSubmit | Matcher: (none) | Flags: async
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"

_INPUT=$(cat)

python3 - <<PYEOF
import json, sys, os, time

raw = '''$_INPUT'''
try:
    data = json.loads(raw)
except Exception:
    data = {}

# Read rate_limits.five_hour.used_percentage
rate_limits = data.get('rate_limits') or {}
five_hour = rate_limits.get('five_hour') or {}
used_pct = five_hour.get('used_percentage', 0) or 0

if not used_pct or float(used_pct) <= 0:
    sys.exit(0)

used_pct = float(used_pct)

# Read session start time from .session-cost
scope = os.environ.get('SCOPE_DIR', os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope'))
cost_file = os.path.join(scope, '.session-cost')

if not os.path.isfile(cost_file):
    sys.exit(0)

try:
    with open(cost_file) as f:
        sc = json.load(f)
    start_str = sc.get('first_updated', '') or sc.get('last_updated', '')
    if not start_str:
        sys.exit(0)
    import calendar
    st = calendar.timegm(time.strptime(start_str, '%Y-%m-%dT%H:%M:%SZ'))
    elapsed_min = (time.time() - st) / 60
except Exception:
    sys.exit(0)

if elapsed_min < 5:
    sys.exit(0)

burn_rate = used_pct / elapsed_min
if burn_rate <= 0:
    sys.exit(0)

time_to_exhaust = (100 - used_pct) / burn_rate

if time_to_exhaust >= 30:
    sys.exit(0)

# Dedup by 10-minute band
warn_file = os.path.join(scope, '.rate-limit-last-warn')
band = int(time.time()) // 600
try:
    if os.path.isfile(warn_file):
        with open(warn_file) as f:
            last_band = int(f.read().strip())
        if last_band == band:
            sys.exit(0)
except Exception:
    pass

try:
    with open(warn_file, 'w') as f:
        f.write(str(band))
except Exception:
    pass

ttx = int(time_to_exhaust)
msg = f'[RATE] At current pace, session exhausts in ~{ttx}m. Consider: eco minimal, fewer subagents, or pause for rate reset.'
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': msg}}))
PYEOF
