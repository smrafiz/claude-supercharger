#!/usr/bin/env bash
# Claude Supercharger — Learn from User Feedback
# Event: UserPromptSubmit
# Detects correction AND reinforcement patterns in user prompts.
# Corrections: what to avoid. Reinforcements: what to keep doing.

set -euo pipefail

_INPUT=$(cat)
PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi

[ -z "$PROMPT" ] && exit 0

PROMPT_LOWER=$(printf '%s\n' "$PROMPT" | tr '[:upper:]' '[:lower:]')
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Project-scoped correction log
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('workspace',{}).get('current_dir') or d.get('cwd',''))" 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
PROJ_HASH=$(printf '%s' "$PROJECT_DIR" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_DIR" | md5 -q 2>/dev/null || echo "global")
PROJ_HASH="${PROJ_HASH:0:8}"

SNIPPET=$(printf '%.200s' "$PROMPT")

# --- Corrections (negative feedback) ---
# Only match if prompt is short (<500 chars) and starts with correction language.
# Long prompts with incidental "not" are not corrections.
if [ ${#PROMPT} -lt 500 ] && [[ "$PROMPT_LOWER" =~ ^(don.t|do not|stop |never |no,? |wrong|i said not|i told you not|not what i asked|i didn.t ask|undo that|revert that|put it back|roll back|go back to|shouldn.t have|too (verbose|long|short|much)|why did you|you forgot|you missed|you broke|that broke|not solved|not fixed|still broken) ]]; then
  LOG="$SCOPE_DIR/.user-corrections-${PROJ_HASH}"
  # Dedup against last 20 entries
  DEDUP=$(printf '%.80s' "$SNIPPET")
  if [ -f "$LOG" ] && tail -20 "$LOG" 2>/dev/null | grep -qF "$DEDUP"; then
    : # skip duplicate
  else
    printf '[%s] CORRECTION: %s\n' "$(date '+%Y-%m-%d %H:%M')" "$SNIPPET" >> "$LOG" 2>/dev/null || true
    echo "[Supercharger] learn: logged correction" >&2
  fi
  exit 0
fi

# --- Reinforcements (positive feedback) ---
# Only match short prompts that are clearly praise, not long prompts with incidental words
if [ ${#PROMPT} -lt 300 ] && [[ "$PROMPT_LOWER" =~ ^(perfect|exactly|yes.*(right|correct|that)|good job|well done|keep doing|that.s what i want|nailed it|spot on|much better|way better|love it|brilliant) ]]; then
  LOG="$SCOPE_DIR/.user-reinforcements-${PROJ_HASH}"
  DEDUP=$(printf '%.80s' "$SNIPPET")
  if [ -f "$LOG" ] && tail -20 "$LOG" 2>/dev/null | grep -qF "$DEDUP"; then
    : # skip duplicate
  else
    printf '[%s] REINFORCED: %s\n' "$(date '+%Y-%m-%d %H:%M')" "$SNIPPET" >> "$LOG" 2>/dev/null || true
    echo "[Supercharger] learn: logged reinforcement" >&2
  fi
  exit 0
fi

exit 0
