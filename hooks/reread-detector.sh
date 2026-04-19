#!/usr/bin/env bash
# Claude Supercharger — Re-Read Detector
# Event: PostToolUse | Matcher: Read
# Warns when Claude re-reads a file that hasn't changed since last read.
# Skips warning if file was modified (legitimate re-read).

set -euo pipefail

_INPUT=$(cat)

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"
READS_FILE="$SCOPE_DIR/.read-history"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Get current mtime
CURRENT_MTIME=$(stat -f '%m' "$FILE_PATH" 2>/dev/null || stat -c '%Y' "$FILE_PATH" 2>/dev/null || echo "0")

# Check if this file was already read
if [ -f "$READS_FILE" ]; then
  PREV_ENTRY=$(grep -F "$FILE_PATH	" "$READS_FILE" 2>/dev/null | tail -1 || echo "")
  if [ -n "$PREV_ENTRY" ]; then
    PREV_MTIME=$(printf '%s' "$PREV_ENTRY" | cut -f2)
    if [ "$CURRENT_MTIME" = "$PREV_MTIME" ]; then
      # Same mtime — file unchanged, warn about re-read
      SHORT=$(basename "$FILE_PATH")
      CONTEXT="[TOKEN TIP] You already read '${SHORT}' and it hasn't changed. Use cached knowledge or a targeted grep instead of re-reading."
      CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
      echo "[Supercharger] reread-detector: ${SHORT} unchanged since last read" >&2
    fi
  fi
fi

# Log this read with mtime (tab-separated: path\tmtime)
printf '%s\t%s\n' "$FILE_PATH" "$CURRENT_MTIME" >> "$READS_FILE" 2>/dev/null || true

# Keep bounded
if [ -f "$READS_FILE" ]; then
  LINES=$(wc -l < "$READS_FILE" | tr -d ' ')
  if [ "$LINES" -gt 100 ]; then
    tail -60 "$READS_FILE" > "$READS_FILE.tmp" 2>/dev/null && mv "$READS_FILE.tmp" "$READS_FILE" 2>/dev/null || true
  fi
fi

exit 0
