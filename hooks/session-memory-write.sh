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
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "")

# --- Branch ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# --- Recent corrections (last 5, project-scoped) ---
CORRECTIONS=""
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJ_HASH=$(printf '%s' "$PROJECT_DIR" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_DIR" | md5 -q 2>/dev/null || echo "global")
PROJ_HASH="${PROJ_HASH:0:8}"
CORRECTIONS_FILE="$SCOPE_DIR/.user-corrections-${PROJ_HASH}"
# Fall back to global file if project-scoped one doesn't exist yet
if [ -f "$CORRECTIONS_FILE" ]; then
  CORRECTIONS=$(tail -5 "$CORRECTIONS_FILE" 2>/dev/null || echo "")
elif [ -f "$SCOPE_DIR/.user-corrections" ]; then
  CORRECTIONS=$(tail -5 "$SCOPE_DIR/.user-corrections" 2>/dev/null || echo "")
fi

# --- Build dense key=value format (~40% fewer tokens than Markdown) ---
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%MZ')
OPEN_CSV=$(printf '%s\n' "$OPEN_FILES" | sed 's/^- //' | grep -v '^$' | tr '\n' ',' | sed 's/,$//' || true)
COMMITS_CSV=$(printf '%s\n' "$RECENT_COMMITS" | grep -v '^$' | sed 's/ /:/' | tr '\n' '|' | sed 's/|$//' || true)
CORR_LINE=$(printf '%s\n' "$CORRECTIONS" | grep -v '^$' | tr '\n' '|' | sed 's/|$//' || true)

CONTENT="mem:${TIMESTAMP} branch:${BRANCH} open:${OPEN_CSV:-none} commits:${COMMITS_CSV:-none} corrections:${CORR_LINE:-none}"

# --- #11 Differential write: skip if open-work and commits unchanged ---
if [ -f "$MEMORY_FILE" ]; then
  PREV=$(cat "$MEMORY_FILE" 2>/dev/null)
  PREV_OPEN=$(printf '%s' "$PREV" | grep -o 'open:[^ ]*' | cut -d: -f2-)
  PREV_COMMITS=$(printf '%s' "$PREV" | grep -o 'commits:[^ ]*' | cut -d: -f2-)
  if [ "$PREV_OPEN" = "${OPEN_CSV:-none}" ] && [ "$PREV_COMMITS" = "${COMMITS_CSV:-none}" ]; then
    echo "[Supercharger] session-memory: no changes, skipping write" >&2
    exit 0
  fi
fi

# Truncate to 2000 chars
printf '%.1200s\n' "$CONTENT" > "$MEMORY_FILE"

echo "[Supercharger] session-memory: wrote $MEMORY_FILE" >&2

# Clean up checkpoint files (successful memory write = no longer needed)
rm -f "$HOME/.claude/supercharger/scope"/.checkpoint-* 2>/dev/null || true

exit 0
