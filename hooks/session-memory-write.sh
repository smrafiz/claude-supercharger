#!/usr/bin/env bash
# Claude Supercharger — Session Memory Writer
# Event: Stop | Matcher: *
# Writes a compressed session summary to .claude/supercharger-memory.md
# in the project root. Injected at next SessionStart by session-memory-inject.sh.
# Opt-out: set SUPERCHARGER_NO_MEMORY=1 in your environment.

set -euo pipefail

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

# Must be in a project with .claude/ dir
[ ! -d ".claude" ] && exit 0

MEMORY_FILE=".claude/supercharger-memory.md"
AUDIT_DIR="$HOME/.claude/supercharger/audit"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"
SCOPE_DIR="$HOME/.claude/supercharger/scope"

# --- Modified files this session ---
MODIFIED_FILES=""
if [ -f "$AUDIT_FILE" ]; then
  MODIFIED_FILES=$(python3 -c "
import json, sys
files = []
for line in open(sys.argv[1]):
    try:
        e = json.loads(line)
        if e.get('tool') in ('Write', 'Edit') and e.get('file'):
            f = e['file']
            if f not in files:
                files.append(f)
    except Exception:
        pass
print('\n'.join('- ' + f for f in files[-15:]))
" "$AUDIT_FILE" 2>/dev/null || echo "")
fi

# --- Recent commits ---
RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || echo "")

# --- Branch ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# --- Active tier ---
TIER=$(cat "$SCOPE_DIR/.tier" 2>/dev/null || echo "lean")

# --- Recent corrections (last 3) ---
CORRECTIONS=""
if [ -f "$SCOPE_DIR/.user-corrections" ]; then
  CORRECTIONS=$(tail -3 "$SCOPE_DIR/.user-corrections" 2>/dev/null || echo "")
fi

# --- Build memory doc ---
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')

cat > "$MEMORY_FILE" << MEMORY
# Session Memory — ${TIMESTAMP}

## Context
- Branch: ${BRANCH}
- Economy: ${TIER}

## Modified This Session
${MODIFIED_FILES:-*(none recorded)*}

## Recent Commits
$(printf '%s\n' "$RECENT_COMMITS" | sed 's/^/- /')

## Recent Corrections
${CORRECTIONS:-*(none)*}
MEMORY

echo "[Supercharger] session-memory: wrote $MEMORY_FILE" >&2
exit 0
