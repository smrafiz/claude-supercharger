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

MSG="[MEM] ${CONTENT}"

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] session-memory: injected $MEMORY_FILE" >&2
exit 0
