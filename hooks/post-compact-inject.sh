#!/usr/bin/env bash
# Claude Supercharger — Post-Compaction Context Injector
# Event: PostCompact | Matcher: (none)
# After context compaction, re-injects session constraints so Claude
# doesn't silently lose established decisions, open files, and economy tier.
# PreCompact (compaction-backup.sh) saves memory first; we read it back here.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.26: one python3 fork does compact-summary parse + memory-file read +
# project-config parse + git status/branch + message build + JSON wrap.
# Was: 1 jq + 1 git rev-parse-git-dir + 1 git status + 1 wc + 3 python3 forks
# (compact_summary, hints, JSON wrap) + 1 git rev-parse-branch = 8 forks.
# Now: 1 python3 fork that runs the 2 git subprocesses itself. ~190ms → ~70ms.
RESULT=$(HOOK_INPUT="$_INPUT" PROJECT_DIR="$PROJECT_DIR" HOOK_SUPPRESS="$HOOK_SUPPRESS" python3 <<'PYEOF' 2>/dev/null
import json, os, subprocess, sys

raw = os.environ.get('HOOK_INPUT', '')
project_dir = os.environ.get('PROJECT_DIR', '')
suppress = os.environ.get('HOOK_SUPPRESS', 'false').lower() in ('true', '1', 'yes')

memory_file = '.claude/supercharger-memory.md'
config_file = '.supercharger.json'

def _g(*cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return ''

# Detect dirty working tree
dirty = bool(_g('git', '-C', project_dir, 'status', '--porcelain'))

# Memory file size
mem_bytes = 0
mem_path = os.path.join(project_dir, memory_file)
if os.path.isfile(mem_path):
    try:
        mem_bytes = os.path.getsize(mem_path)
    except Exception:
        pass

lines = []

# Compact summary
try:
    d = json.loads(raw)
    s = (d.get('compact_summary') or '')[:1500]
    if s:
        lines.append('Compaction summary: ' + s)
except Exception:
    pass

# Memory body (full when dirty or large; stub otherwise)
if os.path.isfile(mem_path):
    if dirty or mem_bytes > 500:
        try:
            with open(mem_path) as f:
                content = f.read(2000)
            if content:
                lines.append(content)
        except Exception:
            pass
    else:
        lines.append(f'Session memory exists (clean tree). Read {memory_file} if context is needed.')

# Project config hints
cfg_path = os.path.join(project_dir, config_file)
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path) as f:
            cd = json.load(f)
        h = cd.get('hints', '')
        if h:
            lines.append('Project hints: ' + h)
    except Exception:
        pass

# Current branch (rev-parse first, then symbolic-ref as v2.6.20 fallback)
branch = _g('git', '-C', project_dir, 'rev-parse', '--abbrev-ref', 'HEAD')
if not branch or branch == 'HEAD':
    branch = _g('git', '-C', project_dir, 'symbolic-ref', '--short', 'HEAD')
if branch:
    lines.append('Current branch: ' + branch)

if not lines:
    sys.exit(0)

msg = '[POST-COMPACT] Context restored after compaction:\n' + '\n'.join(lines) + '\nResume from this state — do not re-read files already in memory.'
print(json.dumps({'systemMessage': msg, 'suppressOutput': suppress}))
PYEOF
)
[ -z "$RESULT" ] && exit 0
printf '%s\n' "$RESULT"

# Signal statusline: memory was restored
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
date +%s > "$SCOPE_DIR/.memory-restored" 2>/dev/null || true

echo "[Supercharger] post-compact-inject: context restored" >&2
exit 0
