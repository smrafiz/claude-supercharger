#!/usr/bin/env bash
# Claude Supercharger — Confidence Gate
# Event: PreToolUse | Matcher: Edit,Write,Bash
# Computes confidence score from recent tool history + signal flags;
# allows, warns, or denies tool calls based on three-tier thresholds.
# Disable: SUPERCHARGER_CONFIDENCE=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_CONFIDENCE:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "confidence-gate" && exit 0
hook_profile_skip "confidence-gate" && exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ -z "$TOOL_NAME" ] && exit 0

case "$TOOL_NAME" in
  Edit|Write) ;;
  Bash)
    BASH_CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    [ -z "$BASH_CMD" ] && exit 0
    DESTRUCTIVE=$(BASH_CMD="$BASH_CMD" python3 -c "
import os, re
cmd = os.environ.get('BASH_CMD', '')
patterns = [
    r'(?:^|[\s;&|\`])(?:/[a-z/]*?)?rm\s+-[a-zA-Z]*r[a-zA-Z]*[\s/]',
    r'(?:^|[\s;&|\`])rm\s+-[a-zA-Z]*r[a-zA-Z]*\s*--\s',
    r'\brm\s+--recursive\b',
    r'\bgit\s+push\s+.*--force\b',
    r'\bgit\s+reset\s+--hard\b',
    r'\bgit\s+clean\s+-[a-zA-Z]*f',
    r'\bdrop\s+(table|database|schema)\b',
    r'\bterraform\s+destroy\b',
    r'\bdocker\s+system\s+prune\b',
    r'\bnpm\s+publish\b',
    r'\b(aws|gcloud)\s+.*delete\b',
]
for p in patterns:
    if re.search(p, cmd, re.IGNORECASE):
        print('1')
        raise SystemExit(0)
print('0')
" 2>/dev/null)
    [ "$DESTRUCTIVE" = "0" ] && exit 0
    ;;
  *) exit 0 ;;
esac

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
TIER="${SUPERCHARGER_TIER:-standard}"
SCOPE_DIR="$HOME/.claude/supercharger/scope"
HISTORY="$SCOPE_DIR/.tool-history-${SESSION_ID}"
HISTORY_LEGACY="$SCOPE_DIR/.tool-history"
REPETITION_FLAG="$SCOPE_DIR/.repetition-flag-${SESSION_ID}"
READ_HISTORY="$SCOPE_DIR/.read-history"

TARGET_FILE=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

REPETITION_FLAGGED=0
[ -f "$REPETITION_FLAG" ] && REPETITION_FLAGGED=1

READ_BEFORE_WRITE_VIOLATION=0
if [ "$TOOL_NAME" = "Edit" ] && [ -n "$TARGET_FILE" ]; then
  if [ -f "$READ_HISTORY" ]; then
    if ! grep -qF "${TARGET_FILE}	" "$READ_HISTORY" 2>/dev/null; then
      READ_BEFORE_WRITE_VIOLATION=1
    fi
  else
    READ_BEFORE_WRITE_VIOLATION=1
  fi
fi

FAILURES_LAST_5=0
HISTORY_SOURCE=""
[ -f "$HISTORY" ] && HISTORY_SOURCE="$HISTORY"
[ -z "$HISTORY_SOURCE" ] && [ -f "$HISTORY_LEGACY" ] && HISTORY_SOURCE="$HISTORY_LEGACY"
if [ -n "$HISTORY_SOURCE" ]; then
  FAILURES_LAST_5=$(grep -F "\"session_id\": \"$SESSION_ID\"" "$HISTORY_SOURCE" 2>/dev/null | tail -5 | grep -c '"success": false' || echo 0)
fi

EVAL=$(FAILURES="$FAILURES_LAST_5" RBW="$READ_BEFORE_WRITE_VIOLATION" REP="$REPETITION_FLAGGED" python3 -c "
import os
fail = int(os.environ.get('FAILURES', 0))
rbw = int(os.environ.get('RBW', 0))
rep = int(os.environ.get('REP', 0))
score = 1.0 - (0.20 * fail) - (0.30 * rbw) - (0.20 * rep)
if score < 0.0: score = 0.0
if score > 1.0: score = 1.0
print(f'{score:.2f}|{1 if score >= 0.7 else 0}|{1 if score >= 0.4 else 0}')
")
SCORE_RAW="${EVAL%%|*}"
REST="${EVAL#*|}"
ABOVE_07="${REST%%|*}"
ABOVE_04="${REST#*|}"

REASON_PARTS=()
[ "$FAILURES_LAST_5" -gt 0 ] && REASON_PARTS+=("$FAILURES_LAST_5 recent failures")
[ "$READ_BEFORE_WRITE_VIOLATION" = "1" ] && REASON_PARTS+=("read-before-write violation")
[ "$REPETITION_FLAGGED" = "1" ] && REASON_PARTS+=("repetition flagged")

REASON_STR=""
if [ "${#REASON_PARTS[@]}" -gt 0 ]; then
  REASON_STR=$(IFS=', '; echo "${REASON_PARTS[*]}")
fi

if [ "$ABOVE_07" = "1" ]; then
  exit 0
fi

case "$TIER" in
  minimal)
    if [ "$ABOVE_04" = "1" ]; then
      MSG="[conf:${SCORE_RAW}→warn]"
    else
      MSG="[conf:${SCORE_RAW}→deny]"
    fi
    ;;
  lean)
    MSG="confidence ${SCORE_RAW}: ${REASON_STR}"
    ;;
  *)
    if [ "$ABOVE_04" = "1" ]; then
      MSG="Confidence gate: ${SCORE_RAW} (warn)
  ${REASON_STR}
Proceed with caution."
    else
      MSG="Confidence gate denied $TOOL_NAME call (score ${SCORE_RAW}):
  ${REASON_STR}"
    fi
    ;;
esac

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

if [ "$ABOVE_04" = "1" ]; then
  printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$MSG_JSON"
fi
exit 0
