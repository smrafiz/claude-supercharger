#!/usr/bin/env bash
# Claude Supercharger — Session Memory Writer
# Event: Stop | Matcher: *
# Writes a compressed session summary to .claude/supercharger-memory.md
# in the project root. Injected at next SessionStart by session-memory-inject.sh.
# Opt-out: set SUPERCHARGER_NO_MEMORY=1 in your environment.

set -euo pipefail

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

# Must be in a project with .claude/ dir
[ ! -d ".claude" ] && exit 0

MEMORY_FILE=".claude/supercharger-memory.md"
AUDIT_DIR="$HOME/.claude/supercharger/audit"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"
SCOPE_DIR="$HOME/.claude/supercharger/scope"

# --- Uncommitted changed files only (open work) ---
OPEN_FILES=$(git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
OPEN_FILES=$(printf '%s\n' "$OPEN_FILES" | sort -u | grep -v '^$' | head -15 | sed 's/^/- /' || echo "")

# --- Recent commits (completed decisions) ---
RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || echo "")

# --- Branch ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# --- Recent corrections (last 3, highest signal) ---
CORRECTIONS=""
if [ -f "$SCOPE_DIR/.user-corrections" ]; then
  CORRECTIONS=$(tail -3 "$SCOPE_DIR/.user-corrections" 2>/dev/null || echo "")
fi

# --- Build memory doc (capped at 500 tokens ~= 2000 chars) ---
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')

CONTENT="# Session Memory — ${TIMESTAMP}

## Open Work (uncommitted changes)
${OPEN_FILES:-*(none)*}

## Recent Commits
$(printf '%s\n' "$RECENT_COMMITS" | sed 's/^/- /')

## Corrections
${CORRECTIONS:-*(none)*}"

# Truncate to 2000 chars
printf '%.2000s\n' "$CONTENT" > "$MEMORY_FILE"

echo "[Supercharger] session-memory: wrote $MEMORY_FILE" >&2
exit 0
