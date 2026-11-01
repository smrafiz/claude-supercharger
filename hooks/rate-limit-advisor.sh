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
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
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

rate_limits = data.get('rate_limits') or {}
scope = os.environ.get('SCOPE_DIR', os.path.join((os.environ.get('HOME') or os.path.expanduser('~')), '.claude', 'supercharger', 'scope'))
_sid = ''.join(c for c in (data.get('session_id') or 'default') if c.isalnum() or c in '_-')[:64] or 'default'


def _pct(window):
    try:
        return float((rate_limits.get(window) or {}).get('used_percentage') or 0)
    except (TypeError, ValueError):
        return 0.0


def five_hour_warning():
    """Pace projection on the 5-hour window: warn when it runs out within 30 minutes."""
    used_pct = _pct('five_hour')
    if used_pct <= 0:
        return None
    cost_file = os.path.join(scope, '.session-cost')
    if not os.path.isfile(cost_file):
        return None
    try:
        with open(cost_file) as f:
            sc = json.load(f)
        start_str = sc.get('first_updated', '') or sc.get('last_updated', '')
        if not start_str:
            return None
        import calendar
        st = calendar.timegm(time.strptime(start_str, '%Y-%m-%dT%H:%M:%SZ'))
        elapsed_min = (time.time() - st) / 60
    except Exception:
        return None
    if elapsed_min < 5:
        return None
    burn_rate = used_pct / elapsed_min
    if burn_rate <= 0:
        return None
    time_to_exhaust = (100 - used_pct) / burn_rate
    if time_to_exhaust >= 30:
        return None
    # Dedup by 10-minute band — session-scoped so one session's warn doesn't
    # suppress another's within the same band (2.21.13).
    warn_file = os.path.join(scope, '.rate-limit-last-warn-' + _sid)
    band = int(time.time()) // 600
    try:
        if os.path.isfile(warn_file):
            with open(warn_file) as f:
                if int(f.read().strip()) == band:
                    return None
    except Exception:
        pass
    try:
        with open(warn_file, 'w') as f:
            f.write(str(band))
    except Exception:
        pass
    return (f'[RATE] At current pace, session exhausts in ~{int(time_to_exhaust)}m. '
            'Consider: eco minimal, fewer subagents, or pause for rate reset.')


def weekly_warning():
    """Weekly window: a pace projection would be wrong (usage builds up across days
    and sessions), so plain thresholds. Each level shows once per weekly window,
    across sessions: the window is keyed by its reset time."""
    used_pct = _pct('seven_day')
    level = 95 if used_pct >= 95 else 90 if used_pct >= 90 else 0
    if not level:
        return None
    window = str((rate_limits.get('seven_day') or {}).get('resets_at') or 'unknown')
    warn_file = os.path.join(scope, '.rate-limit-weekly-warned')
    try:
        with open(warn_file) as f:
            last_window, last_level = f.read().strip().split(' ', 1)
        if last_window == window and int(last_level) >= level:
            return None
    except Exception:
        pass
    try:
        with open(warn_file, 'w') as f:
            f.write(f'{window} {level}')
    except Exception:
        pass
    if level == 95:
        return (f'[RATE] Weekly limit {used_pct:.0f}% used: work may stop before the weekly reset. '
                'Finish or hand off the current task, and keep the rest for after the reset.')
    return (f'[RATE] Weekly limit {used_pct:.0f}% used. '
            'Consider: eco minimal, fewer subagents, and saving large tasks for after the weekly reset.')


msgs = [m for m in (five_hour_warning(), weekly_warning()) if m]
if not msgs:
    sys.exit(0)
msg = ' '.join(msgs)
if suppress:
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'additionalContext': msg}}))
else:
    print(json.dumps({'systemMessage': msg, 'suppressOutput': False}))
PYEOF
