#!/usr/bin/env bash
# Claude Supercharger — Session Checkpoint
# Event: PostToolUse | Matcher: Write,Edit,Bash | Flags: async
# Writes a lightweight checkpoint for crash recovery after every file change.
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "session-checkpoint" && exit 0

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

hook_profile_skip "session-checkpoint" && exit 0

# v2.23.3: debounce the checkpoint write. This hook fires on every Write/Edit/Bash
# and spends ~100ms mostly in 3 git child processes — the top reducible hook cost
# in real-session timing. The checkpoint is a FULL idempotent crash-recovery
# snapshot (not incremental), so skipping a call within the window loses nothing:
# the next write captures fresh state, and git itself still holds the true
# modified-file list. Default 10s window; SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=0
# disables. Gate cost: one `date +%s` fork; marker read/write are bash builtins.
_CKPT_DEBOUNCE="${SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS:-10}"
case "$_CKPT_DEBOUNCE" in ''|*[!0-9]*) _CKPT_DEBOUNCE=10 ;; esac
if [ "$_CKPT_DEBOUNCE" -gt 0 ]; then
  _SID_AFTER="${_INPUT#*\"session_id\":\"}"
  if [ "$_SID_AFTER" != "$_INPUT" ]; then
    _CKPT_SID="${_SID_AFTER%%\"*}"
    case "$_CKPT_SID" in ''|*[!A-Za-z0-9._-]*) _CKPT_SID="" ;; esac
    if [ -n "$_CKPT_SID" ]; then
      _NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
      _CKPT_TS="$SCOPE_DIR/.checkpoint-walk-$_CKPT_SID"
      _LAST=0
      if [ -f "$_CKPT_TS" ]; then read -r _LAST < "$_CKPT_TS" 2>/dev/null || true; fi
      case "$_LAST" in ''|*[!0-9]*) _LAST=0 ;; esac
      if [ "$_NOW_EPOCH" -gt 0 ] && [ "$_LAST" -gt 0 ] \
         && [ $(( _NOW_EPOCH - _LAST )) -lt "$_CKPT_DEBOUNCE" ]; then
        exit 0
      fi
      [ "$_NOW_EPOCH" -gt 0 ] && printf '%s\n' "$_NOW_EPOCH" > "$_CKPT_TS" 2>/dev/null || true
    fi
  fi
fi

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

# `rev-parse --abbrev-ref HEAD` fails on a fresh repo with no commits on some
# git builds (notably the Ubuntu CI runner). `symbolic-ref --short HEAD` works
# regardless of whether HEAD points at a commit. Try both before giving up.
branch = _g('git', '-C', cwd, 'rev-parse', '--abbrev-ref', 'HEAD')
if not branch or branch == 'HEAD':
    branch = _g('git', '-C', cwd, 'symbolic-ref', '--short', 'HEAD')

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
