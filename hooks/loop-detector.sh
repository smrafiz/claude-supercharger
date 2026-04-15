#!/usr/bin/env bash
# Claude Supercharger — Loop Detector
# Event: PostToolUse | Matcher: Bash,Read
# Detects when Claude repeats the same tool call and nudges it to try
# a different approach. Saves 10-50K tokens per caught loop.

set -euo pipefail

_INPUT=$(cat)

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

# Build a fingerprint from tool name + key input
FINGERPRINT=""
case "$TOOL_NAME" in
  Bash)
    CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$CMD" ] && exit 0
    FINGERPRINT="${TOOL_NAME}:${CMD}"
    ;;
  Read)
    FPATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -z "$FPATH" ] && exit 0
    FINGERPRINT="${TOOL_NAME}:${FPATH}"
    ;;
  *)
    exit 0
    ;;
esac

# Hash the fingerprint
HASH=$(printf '%s' "$FINGERPRINT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$FINGERPRINT" | md5 -q 2>/dev/null || echo "")
[ -z "$HASH" ] && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"
LOOP_FILE="$SCOPE_DIR/.loop-history"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Count recent occurrences of this hash (last 20 entries)
COUNT=0
if [ -f "$LOOP_FILE" ]; then
  COUNT=$(tail -20 "$LOOP_FILE" 2>/dev/null | grep -c "^${HASH}$" || echo "0")
fi

# Append current hash
echo "$HASH" >> "$LOOP_FILE" 2>/dev/null || true

# Keep file from growing unbounded (last 50 entries)
if [ -f "$LOOP_FILE" ]; then
  LINES=$(wc -l < "$LOOP_FILE" | tr -d ' ')
  if [ "$LINES" -gt 50 ]; then
    tail -30 "$LOOP_FILE" > "$LOOP_FILE.tmp" 2>/dev/null && mv "$LOOP_FILE.tmp" "$LOOP_FILE" 2>/dev/null || true
  fi
fi

# 3+ repeats = loop
if [ "$COUNT" -ge 2 ]; then
  SHORT=$(printf '%.60s' "$FINGERPRINT" | sed 's/["\]//g')
  CONTEXT="[LOOP DETECTED] You have repeated '${SHORT}' ${COUNT} times. This is wasting context tokens. Try a different approach or ask the user for clarification."
  CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
  echo "[Supercharger] loop-detector: '${SHORT}' repeated ${COUNT}x — nudging Claude" >&2
fi

exit 0
