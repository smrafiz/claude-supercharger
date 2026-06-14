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
# Single python3 fork: parse stdin once, extract both cache fields, compute
# hit rate, update rolling window file, and decide degraded state. Replaces
# the previous 4 sequential python3 forks (~50-70ms × 4 cold-starts each).
HEALTH_FILE="$SCOPE_DIR/.cache-health"
RESULT=$(HEALTH_FILE="$HEALTH_FILE" HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null || echo "skip 0 0 [] no"
import json, os, sys

try:
    data = json.loads(os.environ.get('HOOK_INPUT', '{}'))
except Exception:
    print('skip 0 0 [] no'); sys.exit(0)

usage = data.get('tool_response', {})
if isinstance(usage, dict):
    usage = usage.get('usage', usage)
if not isinstance(usage, dict):
    usage = data.get('usage') or {}
if not isinstance(usage, dict):
    usage = {}

cache_read = int(usage.get('cache_read_input_tokens', 0) or 0)
cache_create = int(usage.get('cache_creation_input_tokens', 0) or 0)
total = cache_read + cache_create

if total == 0:
    print('skip 0 0 [] no'); sys.exit(0)

hit_rate = int(cache_read * 100 / total)

path = os.environ.get('HEALTH_FILE', '')
window = []
if path and os.path.exists(path):
    try:
        with open(path) as f:
            w = json.load(f)
        if isinstance(w, list):
            window = w
    except Exception:
        window = []
window.append(hit_rate)
window = window[-5:]

last3 = window[-3:]
degraded = 'yes' if len(last3) >= 3 and all(r < 50 for r in last3) else 'no'

print(f'ok {cache_read} {cache_create} {hit_rate} {json.dumps(window)} {degraded}')
PYEOF
)

case "$RESULT" in
  skip*) exit 0 ;;
  ok\ *)
    # ok <cache_read> <cache_create> <hit_rate> <window_json> <degraded>
    set -- $RESULT
    CACHE_READ="$2"; CACHE_CREATE="$3"; HIT_RATE="$4"
    # rest of fields after $5 are window (may contain spaces inside json) + degraded
    WINDOW="${RESULT#ok $2 $3 $4 }"
    DEGRADED="${WINDOW##* }"
    WINDOW="${WINDOW% *}"
    printf '%s\n' "$WINDOW" > "$HEALTH_FILE"
    ;;
  *) exit 0 ;;
esac

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
MSG="[CACHE] Hit rate dropped to ${HIT_RATE}%. You may be getting re-billed for full context. Three causes are common: (1) default cache TTL is 5min — if you stepped away or the session is bursty, set 1-hour TTL via the API: cache_control: {type: \"ephemeral\", ttl: \"1h\"}; (2) caches are per-workspace since Feb 2026 (Anthropic API + Azure) — switching workspace gives zero cache hits even with identical prompts; (3) long sessions can drift the cache breakpoint out of the 20-block lookback window. Otherwise consider /compact or starting a fresh session."
echo "[Supercharger] cache-health: hit_rate=${HIT_RATE}% bucket=${BUCKET}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")

if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
