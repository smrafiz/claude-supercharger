#!/usr/bin/env bash
# Claude Supercharger — Guard Canary
# Usage: bash tools/guard-canary.sh [--settings PATH] [--quiet]
#
# Feeds each core guard a call it must stop, through the command REGISTERED in
# settings.json, and checks it answers with a deny or an ask. A presence check
# ("the file exists", "the name is in settings.json") passes while a guard is
# inert: a matcher that no longer matches the tool, a registration pointing at a
# moved file, a hook that exits early. This runs the guard the way Claude Code
# would, so those fail here.
#
# State is isolated (SUPERCHARGER_STATE in a temp dir): canary calls must not
# land in the real block ledger, which feeds [BLOCKS] and the FP corpus.
# Exit 0 when every canary is stopped, 1 otherwise.
set -euo pipefail
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

SETTINGS="$HOME/.claude/settings.json"
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --settings) SETTINGS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT
mkdir -p "$ST/scope" "$ST/proj"

# Run guards with the bash running this script, never a bare 'bash': Windows python
# resolves that through CreateProcess, which searches System32 before PATH and
# finds the WSL launcher (exit 1 without a distro), so every canary read as "let
# it through". Native python needs the Windows spelling of the path.
CANARY_BASH="$BASH"
if command -v cygpath >/dev/null 2>&1; then
  CANARY_BASH=$(cygpath -w -- "$BASH" 2>/dev/null) || CANARY_BASH="$BASH"
fi

SETTINGS="$SETTINGS" ST="$ST" QUIET="$QUIET" CANARY_BASH="$CANARY_BASH" python3 <<'PYEOF'
import json, os, re, subprocess, sys

settings, st, quiet = os.environ['SETTINGS'], os.environ['ST'], os.environ['QUIET'] == '1'
proj = os.path.join(st, 'proj')
home = os.environ.get('HOME') or os.path.expanduser('~')

# guard, tool, tool_input. Each must be denied or asked by that guard alone.
CANARIES = [
    ('safety.sh',               'Bash',  {'command': 'rm -rf /'}),
    ('git-safety.sh',           'Bash',  {'command': 'git push --force origin main'}),
    ('path-guard.sh',           'Write', {'file_path': os.path.join(home, '.ssh', 'authorized_keys'), 'content': 'x'}),
    ('harness-tamper-guard.sh', 'Bash',  {'command': 'ls', 'dangerouslyDisableSandbox': True}),
]

try:
    with open(settings) as f:
        hooks = json.load(f).get('hooks', {}).get('PreToolUse', [])
except (OSError, ValueError) as e:
    print(f'cannot read {settings}: {e}')
    sys.exit(1)

def registered(guard, tool):
    """Commands for `guard` whose matcher selects `tool` (matchers are anchored)."""
    found, unmatched = [], False
    for g in hooks:
        m = g.get('matcher') or ''
        for h in g.get('hooks', []):
            c = h.get('command', '')
            if '/' + guard not in c and not c.startswith(guard):
                continue
            try:
                ok = m == '' or m == '*' or re.fullmatch(m, tool) is not None
            except re.error:
                ok = False
            if ok:
                found.append(c)
            else:
                unmatched = True
    return found, unmatched

env = dict(os.environ, SUPERCHARGER_STATE=st, CLAUDE_CODE_SESSION_ID='canary')
env.pop('CLAUDE_PLUGIN_DATA', None)
bad = 0
for guard, tool, tin in CANARIES:
    cmds, unmatched = registered(guard, tool)
    if not cmds:
        why = f'registered, but its matcher does not select {tool}' if unmatched else 'not registered for PreToolUse'
        print(f'  ✗ {guard}: {why}')
        bad += 1
        continue
    payload = json.dumps({'session_id': 'canary', 'cwd': proj, 'hook_event_name': 'PreToolUse',
                          'tool_name': tool, 'tool_input': tin})
    verdict = ''
    for c in cmds:
        try:
            r = subprocess.run([os.environ.get('CANARY_BASH') or 'bash', '-c', c], input=payload, capture_output=True,
                               text=True, cwd=proj, env=env, timeout=30)
        except subprocess.TimeoutExpired:
            verdict = 'timed out'
            continue
        if r.returncode == 2 or re.search(r'"permissionDecision"\s*:\s*"(deny|ask)"', r.stdout):
            verdict = 'ok'
            break
        verdict = f'let it through (exit {r.returncode})'
    if verdict == 'ok':
        if not quiet:
            print(f'  ✓ {guard}: stopped a {tool} canary')
    else:
        print(f'  ✗ {guard}: {verdict}')
        bad += 1

# Liveness: every other registered PreToolUse command must RUN. The canaries above
# prove four guards deny; this proves the rest are not dead. A missing file, a
# script committed without +x (eight guards ran nowhere on the plugin for three
# months) or a crash is exit 126/127/1, which Claude Code treats as a non-blocking
# error: the call goes ahead unguarded, with nothing on screen.
BENIGN = {'command': 'ls', 'file_path': os.path.join(proj, 'canary.txt'), 'content': 'x',
          'old_string': 'a', 'new_string': 'b', 'url': 'https://example.com',
          'prompt': 'hi', 'query': 'hi', 'description': 'canary'}
core = {g for g, _, _ in CANARIES}
dead, alive = [], 0
for g in hooks:
    m = g.get('matcher') or ''
    tool = re.split(r'[|,]', m)[0].replace('.*', 'x').strip() if m not in ('', '*') else 'Bash'
    try:
        if not re.fullmatch(m or '.*', tool):
            continue
    except re.error:
        continue
    for h in g.get('hooks', []):
        c = h.get('command', '')
        name = (re.search(r'([\w-]+\.(?:sh|py))', c) or [None, c[:40]])[1]
        # Only Supercharger's own hooks: another tool's hook is not ours to score.
        if h.get('type', 'command') != 'command' or name in core or 'supercharger' not in c:
            continue
        payload = json.dumps({'session_id': 'canary', 'cwd': proj, 'hook_event_name': 'PreToolUse',
                              'tool_name': tool, 'tool_input': BENIGN})
        try:
            r = subprocess.run([os.environ.get('CANARY_BASH') or 'bash', '-c', c], input=payload,
                               capture_output=True, text=True, cwd=proj, env=env, timeout=30)
            rc = r.returncode
        except subprocess.TimeoutExpired:
            rc = 'timeout'
        if rc in (0, 2):
            alive += 1
        else:
            why = 'not executable' if rc == 126 else 'not found' if rc == 127 else f'exit {rc}'
            dead.append(f'hook {name} does not run on a {tool} call ({why})')
for d in dead:
    print(f'  ✗ {d}')
if not quiet and not dead:
    print(f'  all {alive} other PreToolUse hooks run')
sys.exit(1 if bad or dead else 0)
PYEOF
