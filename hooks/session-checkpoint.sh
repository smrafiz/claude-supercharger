#!/usr/bin/env bash
# Claude Supercharger — Session Checkpoint
# Event: PostToolUse | Matcher: Write,Edit,Bash | Flags: async
# Writes a lightweight checkpoint for crash recovery after every file change.
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "session-checkpoint" && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)

hook_profile_skip "session-checkpoint" && exit 0

# v2.6.17: one python3 fork does parse + git-files + cost + checkpoint write.
# Was: 5 forks (2 python3 stdin-parse, 1 python3 git, 1 python3 cost, 1 git
# rev-parse). New: 1 python3 fork (3 internal git subprocesses unchanged —
# those dominate any case where git is hit). Median 170ms → ~90ms (-47%).
# Hook is async so it doesn't block, but fires on every Write/Edit/Bash.
HOOK_INPUT="$_INPUT" SCOPE_DIR="$SCOPE_DIR" python3 <<'PYEOF' 2>/dev/null || true
import json, os, subprocess, datetime, sys

raw = os.environ.get('HOOK_INPUT', '')
scope_dir = os.environ.get('SCOPE_DIR', '')

try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

session_id = data.get('session_id') or ''
if not session_id:
    sys.exit(0)

cwd = data.get('cwd') or os.getcwd()

# Git branch + modified files (one python process, three git child processes —
# but no python cold-start tax between them).
def _g(*cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return ''

branch = _g('git', '-C', cwd, 'rev-parse', '--abbrev-ref', 'HEAD')

files = set()
for cmd in (
    ('git', '-C', cwd, 'diff', '--name-only'),
    ('git', '-C', cwd, 'diff', '--cached', '--name-only'),
    ('git', '-C', cwd, 'ls-files', '--others', '--exclude-standard'),
):
    out = _g(*cmd)
    for f in out.splitlines():
        f = f.strip()
        if f:
            files.add(f)
modified = ','.join(sorted(files))

# Cost from .session-cost
cost = ''
cost_file = os.path.join(scope_dir, '.session-cost')
if os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            cd = json.load(f)
        val = cd.get('total_usd', '')
        if val != '':
            cost = '${:.4f}'.format(float(val))
    except Exception:
        pass

ts = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%MZ')
parts = ['ckpt:' + ts]
if branch:   parts.append('branch:' + branch)
if modified: parts.append('files:' + modified)
if cost:     parts.append('cost:' + cost)
line = ' '.join(parts)[:500]

ckpt_file = os.path.join(scope_dir, '.checkpoint-' + session_id)
try:
    with open(ckpt_file, 'w') as f:
        f.write(line + '\n')
except Exception:
    pass
PYEOF

exit 0
