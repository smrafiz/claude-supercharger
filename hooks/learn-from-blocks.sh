#!/usr/bin/env bash
# Claude Supercharger — Session Learnings Injector
# Event: SessionStart
# Injects accumulated learnings: blocked commands, user corrections,
# positive reinforcements, and repeated failure patterns.
# Includes log rotation (30 days) and dedup.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
BLOCKS_LOG="$SCOPE_DIR/.blocked-commands"
CORRECTIONS_LOG="$SCOPE_DIR/.user-corrections"
REINFORCEMENTS_LOG="$SCOPE_DIR/.user-reinforcements"
FAILURES_LOG="$SCOPE_DIR/.failed-commands"

# --- Log rotation: remove entries older than 30 days ---
rotate_log() {
  local file="$1"
  [ ! -f "$file" ] && return
  local cutoff
  cutoff=$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || echo "")
  [ -z "$cutoff" ] && return
  # Keep only entries dated after cutoff (format: [YYYY-MM-DD ...])
  if grep -q "^\[" "$file" 2>/dev/null; then
    awk -v cutoff="$cutoff" '/^\[/{d=substr($0,2,10); if(d>=cutoff) print; next} {print}' "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null || true
  fi
}

rotate_log "$BLOCKS_LOG"
rotate_log "$CORRECTIONS_LOG"
rotate_log "$REINFORCEMENTS_LOG"
rotate_log "$FAILURES_LOG"

# --- Dedup: remove consecutive identical entries ---
dedup_log() {
  local file="$1"
  [ ! -f "$file" ] || [ ! -s "$file" ] && return
  awk '!seen[$0]++' "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null || true
}

dedup_log "$BLOCKS_LOG"
dedup_log "$CORRECTIONS_LOG"
dedup_log "$REINFORCEMENTS_LOG"

# --- Build context (capped at 15 entries per signal) ---
CONTEXT=""

append() {
  if [ -n "$CONTEXT" ]; then
    CONTEXT="${CONTEXT}

$1"
  else
    CONTEXT="$1"
  fi
}

# Blocked commands (last 10)
if [ -f "$BLOCKS_LOG" ] && [ -s "$BLOCKS_LOG" ]; then
  append "[BLOCKED COMMANDS] These were blocked — do not attempt them:
$(tail -10 "$BLOCKS_LOG")"
fi

# User corrections (last 10)
if [ -f "$CORRECTIONS_LOG" ] && [ -s "$CORRECTIONS_LOG" ]; then
  append "[USER CORRECTIONS] The user corrected these — respect them:
$(tail -10 "$CORRECTIONS_LOG")"
fi

# User reinforcements (last 10)
if [ -f "$REINFORCEMENTS_LOG" ] && [ -s "$REINFORCEMENTS_LOG" ]; then
  append "[WHAT WORKS] The user praised these approaches — keep doing them:
$(tail -10 "$REINFORCEMENTS_LOG")"
fi

# Repeated failures (patterns that failed 3+ times, top 5)
if [ -f "$FAILURES_LOG" ] && [ -s "$FAILURES_LOG" ]; then
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
