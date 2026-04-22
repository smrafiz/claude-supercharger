#!/usr/bin/env bash
# Claude Supercharger — Session Memory Injector
# Event: SessionStart | Matcher: *
# Injects .claude/supercharger-memory.md into context if present.
# Written by session-memory-write.sh on Stop.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

MEMORY_FILE="${PROJECT_DIR}/.claude/supercharger-memory.md"

# Checkpoint recovery fallback
if [ ! -f "$MEMORY_FILE" ]; then
  # Check for crash checkpoint
  CKPT=""
  for f in "$HOME/.claude/supercharger/scope"/.checkpoint-*; do
    [ -f "$f" ] || continue
    # Only use if < 24h old
    if python3 -c "import os,time; exit(0 if time.time()-os.path.getmtime('$f')<86400 else 1)" 2>/dev/null; then
      CKPT=$(cat "$f" 2>/dev/null)
      break
    else
      rm -f "$f" 2>/dev/null
    fi
  done
  if [ -n "$CKPT" ]; then
    MSG="[RECOVERY] Restored from mid-session checkpoint: $CKPT"
    CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] session-memory: recovered from checkpoint" >&2
  fi
  exit 0
fi

# Cap at 3000 chars to avoid flooding context
CONTENT=$(head -c 3000 "$MEMORY_FILE" 2>/dev/null || echo "")
[ -z "$CONTENT" ] && exit 0

# Lazy injection: if branch changed or no open work, emit stub only
CURRENT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
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
  # Enrich with live data (v2 enhanced resume)
  ENRICHMENT=""
  # Git diff summary
  DIFF_STAT=$(git -C "$PROJECT_DIR" diff --stat HEAD 2>/dev/null | tail -1 | grep -o '[0-9]* file.*' || echo "")
  [ -n "$DIFF_STAT" ] && ENRICHMENT="${ENRICHMENT} diff:${DIFF_STAT}"
  # Last session cost
  COST_FILE="$HOME/.claude/supercharger/scope/.session-cost"
  if [ -f "$COST_FILE" ]; then
    LAST_COST=$(python3 -c "
import json, os, time
f = '$COST_FILE'
if time.time() - os.path.getmtime(f) < 86400:
    print(json.load(open(f)).get('total_usd', ''))
" 2>/dev/null || echo "")
    [ -n "$LAST_COST" ] && ENRICHMENT="${ENRICHMENT} last_cost:\$${LAST_COST}"
  fi
  # Recent failures
  PROJECT_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")
  PROJ_HASH_ENR=$(printf '%s' "$PROJECT_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "global")
  PROJ_HASH_ENR="${PROJ_HASH_ENR:0:8}"
  FAILURE_LOG="$HOME/.claude/supercharger/scope/.failure-log-${PROJ_HASH_ENR}"
  if [ -f "$FAILURE_LOG" ]; then
    FAILURES=$(tail -10 "$FAILURE_LOG" 2>/dev/null | sort -u | tail -3 | tr '\n' ',' | sed 's/,$//')
    [ -n "$FAILURES" ] && ENRICHMENT="${ENRICHMENT} failures:${FAILURES}"
  fi
  MSG="[MEM] ${CONTENT}${ENRICHMENT}"
fi

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"

echo "[Supercharger] session-memory: injected $MEMORY_FILE" >&2
exit 0
