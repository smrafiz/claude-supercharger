#!/usr/bin/env bash
# Claude Supercharger — Post-Compaction Context Injector
# Event: PostCompact | Matcher: (none)
# After context compaction, re-injects session constraints so Claude
# doesn't silently lose established decisions, open files, and economy tier.
# PreCompact (compaction-backup.sh) saves memory first; we read it back here.

set -euo pipefail

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

MEMORY_FILE=".claude/supercharger-memory.md"
PROJECT_CONFIG=".supercharger.json"

lines=()

# ── Session memory ──
if [ -f "$MEMORY_FILE" ]; then
  CONTENT=$(head -c 2000 "$MEMORY_FILE" 2>/dev/null || echo "")
  if [ -n "$CONTENT" ]; then
    lines+=("$CONTENT")
  fi
fi

# ── Project config hints ──
if [ -f "$PROJECT_CONFIG" ]; then
  HINTS=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PROJECT_CONFIG'))
    h = d.get('hints','')
    if h: print('Project hints: ' + h)
except: pass
" 2>/dev/null || echo "")
  [ -n "$HINTS" ] && lines+=("$HINTS")
fi

# ── Current branch ──
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[ -n "$BRANCH" ] && lines+=("Current branch: $BRANCH")

[ ${#lines[@]} -eq 0 ] && exit 0

# Compose message
MSG="[POST-COMPACT] Context restored after compaction:"$'\n'
for line in "${lines[@]}"; do
  MSG="${MSG}${line}"$'\n'
done
MSG="${MSG}Resume from this state — do not re-read files already in memory."

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")

printf '{"hookSpecificOutput":{"hookEventName":"PostCompact","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] post-compact-inject: context restored" >&2
exit 0
