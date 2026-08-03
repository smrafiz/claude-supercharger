#!/usr/bin/env bash
# Claude Supercharger — Rate Limit Burn Advisor
# Event: UserPromptSubmit | Matcher: (none) | Flags: async
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"
hook_profile_skip "rate-limit-advisor" && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# v2.6.77: $PWD here is the hook runner's CWD, not the project root, so
# .supercharger-debug detection never fired. Use payload cwd like other hooks.
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# 2.21.13: export SCOPE_DIR — the python reads os.environ['SCOPE_DIR'] but bash
# never set it, so under the plugin runtime (state in CLAUDE_PLUGIN_DATA) it fell
# back to ~/.claude and never found .session-cost → the advisor never fired.
HOOK_INPUT="$_INPUT" HOOK_SUPPRESS="$HOOK_SUPPRESS" SCOPE_DIR="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope" python3 - <<'PYEOF'
import json, sys, os, time

suppress = os.environ.get('HOOK_SUPPRESS', 'true').lower() in ('true', '1', 'yes')

try:
    data = json.loads(os.environ.get('HOOK_INPUT', '{}'))
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

# Dedup by 10-minute band — session-scoped so one session's warn doesn't
# suppress another's within the same band (2.21.13).
_sid = ''.join(c for c in (data.get('session_id') or 'default') if c.isalnum() or c in '_-')[:64] or 'default'
warn_file = os.path.join(scope, '.rate-limit-last-warn-' + _sid)
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
if suppress:
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': msg}}))
else:
    print(json.dumps({'systemMessage': msg, 'suppressOutput': False}))
PYEOF
