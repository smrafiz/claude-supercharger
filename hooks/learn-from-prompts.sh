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

SNIPPET=$(printf '%.200s' "$PROMPT")

# --- Corrections (negative feedback) ---
if [[ "$PROMPT_LOWER" =~ (don.t|do not|stop|never|quit|avoid|i said not to|i told you not|wrong|that.s not what i|not what i asked|i didn.t ask|undo that|revert that|put it back|restore|roll back|go back to|shouldn.t have|too (verbose|long|short|much)|why did you|you forgot|you missed|you broke|that broke) ]]; then
  LOG="$SCOPE_DIR/.user-corrections"
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
if [[ "$PROMPT_LOWER" =~ (perfect|exactly|yes.*(right|correct|that)|good job|well done|nice|great|keep doing|that.s what i want|nailed it|spot on|much better|way better|thank you|thanks.*(that|this)|love it|brilliant) ]]; then
  LOG="$SCOPE_DIR/.user-reinforcements"
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
