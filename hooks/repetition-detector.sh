#!/usr/bin/env bash
# Claude Supercharger — Repetition Detector
# Event: PostToolUse | Matcher: Bash,Read
# Merged from loop-detector.sh + reread-detector.sh
# Detects repeated tool calls (loops) and unchanged file re-reads.
# Saves 10-50K tokens per caught loop; prevents redundant context reads.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)

# v2.6.27: one jq fork extracts all 5 fields (cwd, tool_name, command,
# file_path, session_id) using @tsv. Was 3-4 separate jq forks. Median
# 70ms → ~30ms on the common case (no loop, no re-read).
FIELDS=$(printf '%s\n' "$_INPUT" | jq -r '[.cwd // "", .tool_name // "", .tool_input.command // "", .tool_input.file_path // "", .session_id // "default"] | @tsv' 2>/dev/null || true)
# v2.7.44 perf: split the jq @tsv line ONCE with a bash read (IFS=tab) instead of
# 4 separate awk forks. This hook fires on every Bash AND Read (hottest hook).
IFS=$'\t' read -r PROJECT_DIR TOOL_NAME F_CMD F_FPATH _ <<EOF_FIELDS
$FIELDS
EOF_FIELDS
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "repetition-detector" && exit 0

[ -z "$TOOL_NAME" ] && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

MESSAGES=()

# ── Loop detection (Bash + Read) ──
LOOP_FILE="$SCOPE_DIR/.loop-history"

FINGERPRINT=""
case "$TOOL_NAME" in
  Bash)
    [ -z "$F_CMD" ] && FINGERPRINT="" || FINGERPRINT="Bash:${F_CMD}"
    ;;
  Read)
    [ -z "$F_FPATH" ] && FINGERPRINT="" || FINGERPRINT="Read:${F_FPATH}"
    ;;
esac

if [ -n "$FINGERPRINT" ]; then
  HASH=$(printf '%s' "$FINGERPRINT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$FINGERPRINT" | md5 -q 2>/dev/null || echo "")
  if [ -n "$HASH" ]; then
    # tail-then-awk; awk always emits the count, no shell-exit-status games
    COUNT=0
    if [ -f "$LOOP_FILE" ]; then
      COUNT=$(tail -20 "$LOOP_FILE" 2>/dev/null | awk -v h="$HASH" '$0==h{c++} END{print c+0}' || echo 0)
      [ -z "$COUNT" ] && COUNT=0
    fi
    echo "$HASH" >> "$LOOP_FILE" 2>/dev/null || true

    # Trim loop history
    if [ -f "$LOOP_FILE" ]; then
      LINES=$(wc -l < "$LOOP_FILE" | tr -d ' ')
      if [ "$LINES" -gt 50 ]; then
        tail -30 "$LOOP_FILE" > "$LOOP_FILE.$$.tmp" 2>/dev/null && mv "$LOOP_FILE.$$.tmp" "$LOOP_FILE" 2>/dev/null || true
      fi
    fi

    if [ "$COUNT" -ge 2 ]; then
      SHORT=$(printf '%.60s' "$FINGERPRINT" | sed 's/["\]//g')
      MESSAGES+=("[LOOP] '${SHORT}' repeated ${COUNT}x — try different approach")
      echo "[Supercharger] repetition-detector: loop '${SHORT}' repeated ${COUNT}x" >&2
      # session_id was already extracted into FIELDS — no extra fork
      SESSION_ID_REP=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $5}' | tr -cd 'a-zA-Z0-9_-' | head -c 64)
      [ -z "$SESSION_ID_REP" ] && SESSION_ID_REP="default"
      touch "$SCOPE_DIR/.repetition-flag-${SESSION_ID_REP}" 2>/dev/null || true
    fi
  fi
fi

# ── Re-read detection (Read only) ──
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(printf '%s' "$FIELDS" | awk -F'\t' '{print $4}')
  if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
    READS_FILE="$SCOPE_DIR/.read-history"
    # v2.6.78: GNU-first + numeric guard for Linux stat-f portability
    CURRENT_MTIME=$(stat -c '%Y' "$FILE_PATH" 2>/dev/null || stat -f '%m' "$FILE_PATH" 2>/dev/null || echo "")
    case "$CURRENT_MTIME" in ''|*[!0-9]*) CURRENT_MTIME=0 ;; esac

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
        tail -60 "$READS_FILE" > "$READS_FILE.$$.tmp" 2>/dev/null && mv "$READS_FILE.$$.tmp" "$READS_FILE" 2>/dev/null || true
      fi
    fi
  fi
fi

[ ${#MESSAGES[@]} -eq 0 ] && exit 0

# Combine messages and emit
COMBINED=$(printf '%s\n' "${MESSAGES[@]}")
CONTEXT_JSON=$(printf '%s' "$COMBINED" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$COMBINED" | tr -d '"\\' | tr '\n' ' ')")
# v2.7.40: loop/re-read advice is for Claude to act on → additionalContext
# (PostToolUse), not systemMessage (user-only).
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
