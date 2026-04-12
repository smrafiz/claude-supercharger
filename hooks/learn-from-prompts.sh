#!/usr/bin/env bash
# Claude Supercharger — Learn from User Corrections
# Event: UserPromptSubmit
# Detects correction patterns in user prompts and logs them
# so Claude avoids repeating the same mistakes.

set -euo pipefail

_INPUT=$(cat)
PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi

[ -z "$PROMPT" ] && exit 0

PROMPT_LOWER=$(printf '%s\n' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Detect correction patterns
CORRECTION=""

if [[ "$PROMPT_LOWER" =~ (don.t|do not|stop|never|quit|avoid|i said not to|i told you not|wrong|that.s not what i|not what i asked|i didn.t ask) ]]; then
  # Extract a useful snippet (first 200 chars)
  CORRECTION=$(printf '%.200s' "$PROMPT")
fi

# Detect "undo" / "revert" signals (user unhappy with result)
if [[ "$PROMPT_LOWER" =~ (undo that|revert that|put it back|restore|roll back|go back to|shouldn.t have) ]]; then
  CORRECTION=$(printf '%.200s' "$PROMPT")
fi

[ -z "$CORRECTION" ] && exit 0

# Log the correction
LEARNINGS_DIR="$HOME/.claude/supercharger/scope"
CORRECTIONS_LOG="$LEARNINGS_DIR/.user-corrections"
mkdir -p "$LEARNINGS_DIR" 2>/dev/null || true

# Avoid duplicate entries (check last 20 lines)
if [ -f "$CORRECTIONS_LOG" ]; then
  SNIPPET=$(printf '%.80s' "$CORRECTION")
  if tail -20 "$CORRECTIONS_LOG" 2>/dev/null | grep -qF "$SNIPPET"; then
    exit 0
  fi
fi

printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M')" "$CORRECTION" >> "$CORRECTIONS_LOG" 2>/dev/null || true
echo "[Supercharger] learn: logged user correction" >&2

exit 0
