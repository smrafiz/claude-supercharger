#!/usr/bin/env bash
# Claude Supercharger — Session Memory Injector
# Event: SessionStart | Matcher: *
# Injects .claude/supercharger-memory.md into context if present.
# Written by session-memory-write.sh on Stop.

set -euo pipefail

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

MEMORY_FILE=".claude/supercharger-memory.md"

[ ! -f "$MEMORY_FILE" ] && exit 0

# Cap at 3000 chars to avoid flooding context
CONTENT=$(head -c 3000 "$MEMORY_FILE" 2>/dev/null || echo "")
[ -z "$CONTENT" ] && exit 0

# Lazy injection: if branch changed or no open work, emit stub only
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
MEM_BRANCH=$(printf '%s' "$CONTENT" | grep -o 'branch:[^ ]*' | cut -d: -f2- || echo "")
MEM_OPEN=$(printf '%s' "$CONTENT" | grep -o 'open:[^ ]*' | cut -d: -f2- || echo "")

if [ -n "$CURRENT_BRANCH" ] && [ -n "$MEM_BRANCH" ] && [ "$CURRENT_BRANCH" != "$MEM_BRANCH" ]; then
  # Switched branches — stub only, avoid injecting stale open-file list
  MSG="[MEM] prev:branch=${MEM_BRANCH} (ask if context needed)"
elif [ "$MEM_OPEN" = "none" ] || [ -z "$MEM_OPEN" ]; then
  # No open work in memory — minimal stub
  MSG="[MEM] prev:branch=${MEM_BRANCH:-?} no open work"
else
  # Active open work on same branch — inject full memory
  MSG="[MEM] ${CONTENT}"
fi

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] session-memory: injected $MEMORY_FILE" >&2
exit 0
