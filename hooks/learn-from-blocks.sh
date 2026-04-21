#!/usr/bin/env bash
# Claude Supercharger — Session Learnings Injector
# Event: SessionStart
# Injects accumulated learnings: blocked commands, user corrections,
# positive reinforcements, and repeated failure patterns.
# Includes log rotation (30 days) and dedup.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
BLOCKS_LOG="$SCOPE_DIR/.blocked-commands"
FAILURES_LOG="$SCOPE_DIR/.failed-commands"

# Project-scoped corrections/reinforcements
_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
PROJ_HASH=$(printf '%s' "$PROJECT_DIR" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_DIR" | md5 -q 2>/dev/null || echo "global")
PROJ_HASH="${PROJ_HASH:0:8}"
CORRECTIONS_LOG="$SCOPE_DIR/.user-corrections-${PROJ_HASH}"
REINFORCEMENTS_LOG="$SCOPE_DIR/.user-reinforcements-${PROJ_HASH}"
# Fall back to global if project-scoped files don't exist
[ ! -f "$CORRECTIONS_LOG" ] && [ -f "$SCOPE_DIR/.user-corrections" ] && CORRECTIONS_LOG="$SCOPE_DIR/.user-corrections"
[ ! -f "$REINFORCEMENTS_LOG" ] && [ -f "$SCOPE_DIR/.user-reinforcements" ] && REINFORCEMENTS_LOG="$SCOPE_DIR/.user-reinforcements"

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

# --- Build context ---
CONTEXT=""

append() {
  if [ -n "$CONTEXT" ]; then
    CONTEXT="${CONTEXT}

$1"
  else
    CONTEXT="$1"
  fi
}

# Blocked commands — compressed to category counts (top 8 by frequency)
if [ -f "$BLOCKS_LOG" ] && [ -s "$BLOCKS_LOG" ]; then
  COMPRESSED=$(python3 - "$BLOCKS_LOG" <<'PYEOF'
import sys, re
from collections import Counter

path = sys.argv[1]
counts = Counter()
last_seen = {}

with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        # Strip timestamp: [YYYY-MM-DD HH:MM] REASON — COMMAND
        m = re.match(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\] (.+)$', line)
        if not m:
            continue
        date, rest = m.group(1), m.group(2)
        # Extract reason: text before " — COMMAND" (last " — " separator)
        # Reason may itself contain " — " so take up to first 80 chars as key
        reason = rest.split(' — ')[0].strip()[:80]
        counts[reason] += 1
        last_seen[reason] = date[:10]

if not counts:
    sys.exit(0)

lines = []
for reason, count in counts.most_common(8):
    lines.append(f"- {reason} (blocked {count}x, last: {last_seen[reason]})")
print('\n'.join(lines))
PYEOF
)
  if [ -n "$COMPRESSED" ]; then
    append "[BLOCKS] ${COMPRESSED}"
  fi
fi

# User corrections (last 5)
if [ -f "$CORRECTIONS_LOG" ] && [ -s "$CORRECTIONS_LOG" ]; then
  append "[CORR] $(tail -5 "$CORRECTIONS_LOG" | sed 's/\[.*\] CORRECTION: //' | tr '\n' '|' | sed 's/|$//')"
fi

# User reinforcements (last 5)
if [ -f "$REINFORCEMENTS_LOG" ] && [ -s "$REINFORCEMENTS_LOG" ]; then
  append "[WORKS] $(tail -5 "$REINFORCEMENTS_LOG" | sed 's/\[.*\] REINFORCED: //' | tr '\n' '|' | sed 's/|$//')"
fi

# Repeated failures (patterns that failed 3+ times, top 5)
if [ -f "$FAILURES_LOG" ] && [ -s "$FAILURES_LOG" ]; then
  REPEATED=$(sort "$FAILURES_LOG" 2>/dev/null | sed 's/^\[.*\] exit=[0-9]* — //' | sort | uniq -c | sort -rn | awk '$1 >= 3 {$1=""; print}' | head -5)
  if [ -n "$REPEATED" ]; then
    append "[FAILS] ${REPEATED}"
  fi
fi

[ -z "$CONTEXT" ] && exit 0

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"systemMessage":%s}\n' "$CONTEXT_JSON"

exit 0
