#!/usr/bin/env bash
# Claude Supercharger — Post-Compaction Context Injector
# Event: PostCompact | Matcher: (none)
# After context compaction, re-injects session constraints so Claude
# doesn't silently lose established decisions, open files, and economy tier.
# PreCompact (compaction-backup.sh) saves memory first; we read it back here.

set -euo pipefail

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

_INPUT=$(cat)

MEMORY_FILE=".claude/supercharger-memory.md"
PROJECT_CONFIG=".supercharger.json"

lines=()

# ── Compact summary (what Claude Code actually preserved) ──
COMPACT_SUMMARY=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    s = d.get('compact_summary', '')
    if s: print(s[:1500])
except: pass
" 2>/dev/null || echo "")
[ -n "$COMPACT_SUMMARY" ] && lines+=("Compaction summary: ${COMPACT_SUMMARY}")

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

printf '{"systemMessage":%s,"suppressOutput":true}\n' "$CONTEXT_JSON"

# Signal statusline: memory was restored
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
date +%s > "$SCOPE_DIR/.memory-restored" 2>/dev/null || true

echo "[Supercharger] post-compact-inject: context restored" >&2
exit 0
