#!/usr/bin/env bash
# Claude Supercharger — Compaction Backup Hook
# Event: PreCompact | Matcher: (none)
# Saves conversation transcript before context compaction.
# Also ensures summaries directory exists for Claude to write session summaries.

set -euo pipefail

BACKUP_DIR="$HOME/.claude/backups/transcripts"
SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"
mkdir -p "$BACKUP_DIR"
mkdir -p "$SUMMARIES_DIR"
chmod 700 "$BACKUP_DIR"
chmod 700 "$SUMMARIES_DIR"

TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/$TIMESTAMP.md"

_INPUT=$(cat)
printf '%s\n' "$_INPUT" > "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

echo "[Supercharger] compaction-backup: transcript backed up to $BACKUP_FILE" >&2
echo "[Supercharger] compaction-backup: session summary directory ready at $SUMMARIES_DIR" >&2

# Rotate: remove backups older than 30 days (at most once per day)
ROTATION_CHECK="$BACKUP_DIR/.last-rotation"
NOW=$(date +%s)
LAST_ROTATION=$(cat "$ROTATION_CHECK" 2>/dev/null || echo "0")
[ -z "$LAST_ROTATION" ] && LAST_ROTATION=0
if (( NOW - LAST_ROTATION > 86400 )); then
  find "$BACKUP_DIR" -name "*.md" -mtime +30 -delete 2>/dev/null || true
  echo "$NOW" > "$ROTATION_CHECK"
fi

# v2.6.34: parallelize the two inline child hooks (session-memory-write and
# lesson-record). Both read transcript / scope files independently; running
# them concurrently overlaps the IO + python cold-starts. wait blocks until
# both finish — still race-free vs the post-fix in v2.6.5. Cuts ~70ms off
# the sync PreCompact path.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/session-memory-write.sh" ]; then
  printf '%s\n' "$_INPUT" | bash "$HOOKS_DIR/session-memory-write.sh" 2>/dev/null &
fi
if [ -f "$HOOKS_DIR/lesson-record.sh" ]; then
  printf '%s\n' "$_INPUT" | bash "$HOOKS_DIR/lesson-record.sh" 2>/dev/null &
fi
wait

# v2.6.34: one python3 fork does git diff + cost read + JSON wrap.
# Was 3 forks (git diff + tr + sed pipeline, python3 cost read, jq -Rs).
# git diff stays a subprocess INSIDE python — same total cost, one fewer
# python cold-start.
SCOPE_DIR="$HOME/.claude/supercharger/scope"
GUIDANCE=$(SCOPE_DIR="$SCOPE_DIR" python3 <<'PYEOF' 2>/dev/null
import json, os, subprocess

scope_dir = os.environ['SCOPE_DIR']
parts = []

# Modified files
try:
    out = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'],
                                  stderr=subprocess.DEVNULL, timeout=2).decode()
    files = [f for f in out.splitlines() if f][:10]
    if files:
        parts.append('PRESERVE modified files: ' + ','.join(files) + '.')
except Exception:
    pass

# Economy tier
try:
    with open(os.path.join(scope_dir, '.economy-tier')) as f:
        tier = f.read().strip()
    if tier:
        parts.append('PRESERVE economy: ' + tier + '.')
except Exception:
    pass

# Session cost
try:
    with open(os.path.join(scope_dir, '.session-cost')) as f:
        cost = json.load(f).get('total_usd', '')
    if cost != '':
        parts.append(f'Session cost so far: ${cost}.')
except Exception:
    pass

if not parts:
    exit(0)
guidance = '[COMPACT] ' + ' '.join(parts) + ' DISCARD: full file contents, verbose tool output, completed task details.'
print(json.dumps({'systemMessage': guidance, 'suppressOutput': True}))
PYEOF
)

[ -n "$GUIDANCE" ] && printf '%s\n' "$GUIDANCE"
exit 0
