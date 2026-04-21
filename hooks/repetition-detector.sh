#!/usr/bin/env bash
# Claude Supercharger — Repetition Detector
# Event: PostToolUse | Matcher: Bash,Read
# Merged from loop-detector.sh + reread-detector.sh
# Detects repeated tool calls (loops) and unchanged file re-reads.
# Saves 10-50K tokens per caught loop; prevents redundant context reads.

set -euo pipefail

_INPUT=$(cat)

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

MESSAGES=()

# ── Loop detection (Bash + Read) ──
LOOP_FILE="$SCOPE_DIR/.loop-history"

FINGERPRINT=""
case "$TOOL_NAME" in
  Bash)
    CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$CMD" ] && FINGERPRINT="" || FINGERPRINT="Bash:${CMD}"
    ;;
  Read)
    FPATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -z "$FPATH" ] && FINGERPRINT="" || FINGERPRINT="Read:${FPATH}"
    ;;
esac

if [ -n "$FINGERPRINT" ]; then
  HASH=$(printf '%s' "$FINGERPRINT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$FINGERPRINT" | md5 -q 2>/dev/null || echo "")
  if [ -n "$HASH" ]; then
    COUNT=0
    [ -f "$LOOP_FILE" ] && COUNT=$(tail -20 "$LOOP_FILE" 2>/dev/null | grep -c "^${HASH}$" || echo "0")
    echo "$HASH" >> "$LOOP_FILE" 2>/dev/null || true

    # Trim loop history
    if [ -f "$LOOP_FILE" ]; then
      LINES=$(wc -l < "$LOOP_FILE" | tr -d ' ')
      if [ "$LINES" -gt 50 ]; then
        tail -30 "$LOOP_FILE" > "$LOOP_FILE.tmp" 2>/dev/null && mv "$LOOP_FILE.tmp" "$LOOP_FILE" 2>/dev/null || true
      fi
    fi

    if [ "$COUNT" -ge 2 ]; then
      SHORT=$(printf '%.60s' "$FINGERPRINT" | sed 's/["\]//g')
      MESSAGES+=("[LOOP] '${SHORT}' repeated ${COUNT}x — try different approach")
      echo "[Supercharger] repetition-detector: loop '${SHORT}' repeated ${COUNT}x" >&2
    fi
  fi
fi

# ── Re-read detection (Read only) ──
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
    READS_FILE="$SCOPE_DIR/.read-history"
    CURRENT_MTIME=$(stat -f '%m' "$FILE_PATH" 2>/dev/null || stat -c '%Y' "$FILE_PATH" 2>/dev/null || echo "0")

    if [ -f "$READS_FILE" ]; then
      PREV_ENTRY=$(grep -F "${FILE_PATH}	" "$READS_FILE" 2>/dev/null | tail -1 || echo "")
      if [ -n "$PREV_ENTRY" ]; then
        PREV_MTIME=$(printf '%s' "$PREV_ENTRY" | cut -f2)
        if [ "$CURRENT_MTIME" = "$PREV_MTIME" ]; then
          SHORT=$(basename "$FILE_PATH")
          MESSAGES+=("[TOKEN TIP] You already read '${SHORT}' and it hasn't changed. Use cached knowledge or a targeted grep instead of re-reading.")
          echo "[Supercharger] repetition-detector: ${SHORT} unchanged since last read" >&2
        fi
      fi
    fi

    printf '%s\t%s\n' "$FILE_PATH" "$CURRENT_MTIME" >> "$READS_FILE" 2>/dev/null || true

    # Trim read history
    if [ -f "$READS_FILE" ]; then
      LINES=$(wc -l < "$READS_FILE" | tr -d ' ')
      if [ "$LINES" -gt 100 ]; then
        tail -60 "$READS_FILE" > "$READS_FILE.tmp" 2>/dev/null && mv "$READS_FILE.tmp" "$READS_FILE" 2>/dev/null || true
      fi
    fi
  fi
fi

[ ${#MESSAGES[@]} -eq 0 ] && exit 0

# Combine messages and emit
COMBINED=$(printf '%s\n' "${MESSAGES[@]}")
CONTEXT_JSON=$(printf '%s' "$COMBINED" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$COMBINED" | tr -d '"\\' | tr '\n' ' ')")
printf '{"systemMessage":%s}\n' "$CONTEXT_JSON"

exit 0
