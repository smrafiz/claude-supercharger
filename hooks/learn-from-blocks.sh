#!/usr/bin/env bash
# Claude Supercharger — Session Learnings Injector
# Event: SessionStart
# Injects accumulated learnings from blocked commands and user corrections
# so Claude avoids repeating the same mistakes.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
BLOCKS_LOG="$SCOPE_DIR/.blocked-commands"
CORRECTIONS_LOG="$SCOPE_DIR/.user-corrections"

CONTEXT=""

# Blocked commands
if [ -f "$BLOCKS_LOG" ] && [ -s "$BLOCKS_LOG" ]; then
  RECENT_BLOCKS=$(tail -10 "$BLOCKS_LOG")
  CONTEXT="[BLOCKED COMMANDS] These were blocked in recent sessions — do not attempt them:
${RECENT_BLOCKS}"
fi

# User corrections
if [ -f "$CORRECTIONS_LOG" ] && [ -s "$CORRECTIONS_LOG" ]; then
  RECENT_CORRECTIONS=$(tail -10 "$CORRECTIONS_LOG")
  if [ -n "$CONTEXT" ]; then
    CONTEXT="${CONTEXT}

[USER CORRECTIONS] The user previously corrected these behaviors — respect them:
${RECENT_CORRECTIONS}"
  else
    CONTEXT="[USER CORRECTIONS] The user previously corrected these behaviors — respect them:
${RECENT_CORRECTIONS}"
  fi
fi

[ -z "$CONTEXT" ] && exit 0

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
