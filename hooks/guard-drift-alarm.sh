#!/usr/bin/env bash
# Claude Supercharger — Guard Drift Alarm
# Event: SessionStart
#
# A registered guard whose script is missing or not executable never runs: Claude
# Code reports exit 126/127 as a non-blocking error and the call goes ahead
# unguarded, with nothing on screen. Eight guards shipped that way to plugin users
# from 2026-07-19 to 2026-10-19 and nothing noticed, because /sc-health is only run
# on request. This checks at every session start and says so in the first message.
#
# Static on purpose: the full guard canary RUNS every hook (~40s), far too slow to
# block a session start. Existence + executable bit covers the class that happened;
# a guard that starts but crashes is /sc-health's job (and onFailure "block" denies
# its calls meanwhile). One python fork per session.
# Disable: SUPERCHARGER_DRIFT_ALARM=0
set -uo pipefail
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true
[ "${SUPERCHARGER_DRIFT_ALARM:-1}" = 0 ] && exit 0

SC_SETTINGS="${SUPERCHARGER_DRIFT_SETTINGS:-$HOME/.claude/settings.json}" \
SC_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}" python3 - <<'PY' 2>/dev/null || exit 0
import json, os, shlex

def commands(path, root=''):
    try:
        hooks = json.load(open(path)).get('hooks') or {}
    except (OSError, ValueError, AttributeError):
        return []
    out = []
    for groups in hooks.values():
        for g in groups if isinstance(groups, list) else []:
            for h in g.get('hooks', []) if isinstance(g, dict) else []:
                c = h.get('command') or ''
                if h.get('type', 'command') == 'command' and c:
                    out.append(c.replace('${CLAUDE_PLUGIN_ROOT}', root))
    return out

root = os.environ.get('SC_PLUGIN_ROOT', '')
cmds = [c for c in commands(os.environ['SC_SETTINGS']) if 'supercharger' in c]
if root:
    cmds += commands(os.path.join(root, 'hooks', 'hooks.json'), root)

dead = {}
for c in cmds:
    try:
        toks = shlex.split(c, comments=True)
    except ValueError:
        continue
    # The script is the first token naming a .sh/.py file. It runs as the command
    # itself (needs +x) unless an interpreter token comes before it.
    for i, t in enumerate(toks):
        if t.endswith(('.sh', '.py')) and '/' in t:
            via = i > 0 and os.path.basename(toks[0]) in ('bash', 'sh', 'python3', 'python')
            if not os.path.isfile(t):
                dead[os.path.basename(t)] = 'missing'
            elif not via and not os.access(t, os.X_OK):
                dead[os.path.basename(t)] = 'not executable'
            break

if dead:
    names = ', '.join('%s (%s)' % kv for kv in sorted(dead.items())[:8])
    more = '' if len(dead) <= 8 else ' and %d more' % (len(dead) - 8)
    msg = ('[GUARDS] %d Supercharger guard(s) cannot run, so Claude Code lets every call '
           'through them: %s%s. Re-run the installer (/sc-update) and check /sc-health.'
           % (len(dead), names, more))
    print(json.dumps({'systemMessage': msg,
                      'hookSpecificOutput': {'hookEventName': 'SessionStart',
                                             'additionalContext': msg}}))
PY
exit 0
