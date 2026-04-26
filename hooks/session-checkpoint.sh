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

SESSION_ID=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cwd') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$SESSION_ID" ] && exit 0
hook_profile_skip "session-checkpoint" && exit 0
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

# Get git branch (graceful fallback)
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# Collect modified files (staged + unstaged + untracked), comma-separated
MODIFIED_FILES=$(python3 -c "
import subprocess, sys

cwd = sys.argv[1]
files = set()
for cmd in [
    ['git', '-C', cwd, 'diff', '--name-only'],
    ['git', '-C', cwd, 'diff', '--cached', '--name-only'],
    ['git', '-C', cwd, 'ls-files', '--others', '--exclude-standard'],
]:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode()
        for f in out.strip().splitlines():
            f = f.strip()
            if f:
                files.add(f)
    except Exception:
        pass
print(','.join(sorted(files)))
" "$PROJECT_DIR" 2>/dev/null || true)

# Read cost from .session-cost file (total_usd field)
COST=""
COST_FILE="$SCOPE_DIR/.session-cost"
if [ -f "$COST_FILE" ]; then
  COST=$(python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    val = d.get('total_usd', '')
    if val != '':
        print('\${:.4f}'.format(float(val)))
except Exception:
    pass
" "$COST_FILE" 2>/dev/null || true)
fi

# Build checkpoint line
TS=$(date -u +"%Y-%m-%dT%H:%MZ" 2>/dev/null || echo "")
LINE="ckpt:${TS}"
[ -n "$BRANCH" ]         && LINE="${LINE} branch:${BRANCH}"
[ -n "$MODIFIED_FILES" ] && LINE="${LINE} files:${MODIFIED_FILES}"
[ -n "$COST" ]           && LINE="${LINE} cost:${COST}"

# Cap at 500 chars
LINE="${LINE:0:500}"

# Write checkpoint (overwrite, not append)
CKPT_FILE="$SCOPE_DIR/.checkpoint-${SESSION_ID}"
printf '%s\n' "$LINE" > "$CKPT_FILE"

exit 0
