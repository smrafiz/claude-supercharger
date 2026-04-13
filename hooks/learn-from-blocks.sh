#!/usr/bin/env bash
# Claude Supercharger — Session Learnings Injector
# Event: SessionStart
# Injects accumulated learnings: blocked commands, user corrections,
# positive reinforcements, and repeated failure patterns.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
BLOCKS_LOG="$SCOPE_DIR/.blocked-commands"
CORRECTIONS_LOG="$SCOPE_DIR/.user-corrections"
REINFORCEMENTS_LOG="$SCOPE_DIR/.user-reinforcements"
FAILURES_LOG="$SCOPE_DIR/.failed-commands"

CONTEXT=""

append() {
  if [ -n "$CONTEXT" ]; then
    CONTEXT="${CONTEXT}

$1"
  else
    CONTEXT="$1"
  fi
}

# Blocked commands
if [ -f "$BLOCKS_LOG" ] && [ -s "$BLOCKS_LOG" ]; then
  append "[BLOCKED COMMANDS] These were blocked — do not attempt them:
$(tail -10 "$BLOCKS_LOG")"
fi

# User corrections (negative)
if [ -f "$CORRECTIONS_LOG" ] && [ -s "$CORRECTIONS_LOG" ]; then
  append "[USER CORRECTIONS] The user corrected these — respect them:
$(tail -10 "$CORRECTIONS_LOG")"
fi

# User reinforcements (positive)
if [ -f "$REINFORCEMENTS_LOG" ] && [ -s "$REINFORCEMENTS_LOG" ]; then
  append "[WHAT WORKS] The user praised these approaches — keep doing them:
$(tail -10 "$REINFORCEMENTS_LOG")"
fi

# Repeated failures
if [ -f "$FAILURES_LOG" ] && [ -s "$FAILURES_LOG" ]; then
  # Only inject patterns that failed 3+ times
  REPEATED=$(sort "$FAILURES_LOG" 2>/dev/null | sed 's/^\[.*\] exit=[0-9]* — //' | sort | uniq -c | sort -rn | awk '$1 >= 3 {$1=""; print}' | head -5)
  if [ -n "$REPEATED" ]; then
    append "[REPEATED FAILURES] These commands fail consistently — try different approaches:
${REPEATED}"
  fi
fi

[ -z "$CONTEXT" ] && exit 0

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
