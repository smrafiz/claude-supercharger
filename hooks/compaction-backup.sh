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

exit 0
