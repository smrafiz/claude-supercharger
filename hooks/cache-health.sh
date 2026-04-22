#!/usr/bin/env bash
# Claude Supercharger — Cache Health Monitor
# Event: PostToolUse | Matcher: * | Flags: async
# Samples cache hit rate every 5th call. Warns when degraded (<50% for 3 consecutive readings).

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# ── Step 1: Counter — only proceed every 5th call ───────────────────────────
COUNTER_FILE="$SCOPE_DIR/.cache-health-counter"
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=${COUNT%%.*}
fi
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 5)) -ne 0 ] && exit 0

# ── Step 2: Extract cache token fields from tool_response.usage ─────────────
CACHE_READ=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    usage = data.get('tool_response', {})
    if isinstance(usage, dict):
        usage = usage.get('usage', usage)
    if not isinstance(usage, dict):
        usage = data.get('usage') or {}
    if not isinstance(usage, dict):
        usage = {}
    print(int(usage.get('cache_read_input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

CACHE_CREATE=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    usage = data.get('tool_response', {})
    if isinstance(usage, dict):
        usage = usage.get('usage', usage)
    if not isinstance(usage, dict):
        usage = data.get('usage') or {}
    if not isinstance(usage, dict):
        usage = {}
    print(int(usage.get('cache_creation_input_tokens', 0) or 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

# ── Step 3: Skip if no cache token data ─────────────────────────────────────
TOTAL_CACHE=$((CACHE_READ + CACHE_CREATE))
[ "$TOTAL_CACHE" -eq 0 ] && exit 0

# ── Step 4: Calculate hit rate ───────────────────────────────────────────────
HIT_RATE=$(python3 -c "
read = $CACHE_READ
create = $CACHE_CREATE
total = read + create
if total == 0:
    print(0)
else:
    print(int(read * 100 / total))
" 2>/dev/null || echo "0")

# ── Step 5: Append to rolling window (keep last 5) ──────────────────────────
HEALTH_FILE="$SCOPE_DIR/.cache-health"
WINDOW=$(python3 -c "
import json, os
path = '$HEALTH_FILE'
window = []
if os.path.exists(path):
    try:
        with open(path) as f:
            window = json.load(f)
        if not isinstance(window, list):
            window = []
    except Exception:
        window = []
window.append($HIT_RATE)
window = window[-5:]
print(json.dumps(window))
" 2>/dev/null || echo "[$HIT_RATE]")
printf '%s\n' "$WINDOW" > "$HEALTH_FILE"

# ── Step 6: Check if last 3 readings all < 50% ───────────────────────────────
DEGRADED=$(python3 -c "
import json
try:
    window = json.loads('$WINDOW')
    last3 = window[-3:]
    if len(last3) >= 3 and all(r < 50 for r in last3):
        print('yes')
    else:
        print('no')
except Exception:
    print('no')
" 2>/dev/null || echo "no")

[ "$DEGRADED" != "yes" ] && exit 0

# ── Step 7: Dedup by 10% bucket ─────────────────────────────────────────────
DEDUP_FILE="$SCOPE_DIR/.cache-health-dedup"
BUCKET=$(( (HIT_RATE / 10) * 10 ))
PREV_BUCKET=""
if [ -f "$DEDUP_FILE" ]; then
  PREV_BUCKET=$(cat "$DEDUP_FILE" 2>/dev/null || echo "")
fi
if [ "$BUCKET" = "$PREV_BUCKET" ]; then
  exit 0
fi
printf '%s\n' "$BUCKET" > "$DEDUP_FILE"

# ── Emit warning ─────────────────────────────────────────────────────────────
MSG="[CACHE] Hit rate dropped to ${HIT_RATE}%. You may be getting re-billed for full context. Consider /compact or starting a fresh session."
echo "[Supercharger] cache-health: hit_rate=${HIT_RATE}% bucket=${BUCKET}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")

if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
