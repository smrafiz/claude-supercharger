#!/usr/bin/env bash
# Claude Supercharger — Re-Read Detector
# Event: PostToolUse | Matcher: Read
# Warns when Claude re-reads a file it already read this session.
# 65% of Read calls are re-reads — this nudges Claude to use cached knowledge.

set -euo pipefail

_INPUT=$(cat)

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"
READS_FILE="$SCOPE_DIR/.read-history"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Check if this file was already read
if [ -f "$READS_FILE" ] && grep -qF "$FILE_PATH" "$READS_FILE" 2>/dev/null; then
  SHORT=$(basename "$FILE_PATH")
  CONTEXT="[TOKEN TIP] You already read '${SHORT}' this session. If you need to check if it changed, use a targeted grep or diff instead of re-reading the full file."
  CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
  echo "[Supercharger] reread-detector: ${SHORT} already read — nudged" >&2
fi

# Log this read
echo "$FILE_PATH" >> "$READS_FILE" 2>/dev/null || true

# Keep bounded (last 100 reads)
if [ -f "$READS_FILE" ]; then
  LINES=$(wc -l < "$READS_FILE" | tr -d ' ')
  if [ "$LINES" -gt 100 ]; then
    tail -60 "$READS_FILE" > "$READS_FILE.tmp" 2>/dev/null && mv "$READS_FILE.tmp" "$READS_FILE" 2>/dev/null || true
  fi
fi

exit 0
