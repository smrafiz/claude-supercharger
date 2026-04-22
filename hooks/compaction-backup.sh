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

INPUT=$(cat)
echo "$INPUT" > "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

echo "Transcript backed up to $BACKUP_FILE" >&2
echo "Session summary directory ready at $SUMMARIES_DIR" >&2

# Rotate: remove backups older than 30 days (at most once per day)
ROTATION_CHECK="$BACKUP_DIR/.last-rotation"
NOW=$(date +%s)
LAST_ROTATION=$(cat "$ROTATION_CHECK" 2>/dev/null || echo "0")
[ -z "$LAST_ROTATION" ] && LAST_ROTATION=0
if (( NOW - LAST_ROTATION > 86400 )); then
  find "$BACKUP_DIR" -name "*.md" -mtime +30 -delete 2>/dev/null || true
  echo "$NOW" > "$ROTATION_CHECK"
fi

# Update session memory before context is wiped
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/session-memory-write.sh" ]; then
  echo "" | bash "$HOOKS_DIR/session-memory-write.sh" 2>/dev/null || true
fi

# Inject session-specific compaction guidance
GUIDANCE=""

# Modified files
MODIFIED=$(git diff --name-only HEAD 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//' || echo "")
[ -n "$MODIFIED" ] && GUIDANCE="${GUIDANCE}PRESERVE modified files: ${MODIFIED}. "

# Economy tier
TIER=$(cat "$HOME/.claude/supercharger/scope/.economy-tier" 2>/dev/null || echo "")
[ -n "$TIER" ] && GUIDANCE="${GUIDANCE}PRESERVE economy: ${TIER}. "

# Session cost
if [ -f "$HOME/.claude/supercharger/scope/.session-cost" ]; then
  COST=$(python3 -c "import json; print(json.load(open('$HOME/.claude/supercharger/scope/.session-cost')).get('total_usd',''))" 2>/dev/null || echo "")
  [ -n "$COST" ] && GUIDANCE="${GUIDANCE}Session cost so far: \$${COST}. "
fi

if [ -n "$GUIDANCE" ]; then
  GUIDANCE="[COMPACT] ${GUIDANCE}DISCARD: full file contents, verbose tool output, completed task details."
  CONTEXT_JSON=$(printf '%s' "$GUIDANCE" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$GUIDANCE" | tr -d '"\\' | tr '\n' ' ')")
  printf '{"systemMessage":%s,"suppressOutput":true}\n' "$CONTEXT_JSON"
fi

exit 0
