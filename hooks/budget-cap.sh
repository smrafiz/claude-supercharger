#!/usr/bin/env bash
# Claude Supercharger — Budget Cap Hook
# Event: PostToolUse (accumulator) | PreToolUse check (blocker) | Matcher: (none)
# Modes:
#   (no arg)  — PostToolUse accumulator: reads token usage, calculates cost, writes .session-cost
#   check     — PreToolUse blocker: reads .session-cost, warns at 80%, blocks at 100%

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

MODE="${1:-accumulate}"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

COST_FILE="$SCOPE_DIR/.session-cost"
COST_TMP="$SCOPE_DIR/.session-cost.$$.tmp"

# ── accumulate (PostToolUse) ───────────────────────────────────────────────────
if [[ "$MODE" == "accumulate" ]]; then
  _INPUT=$(cat)

  # Extract all usage fields in one Python call
  USAGE_FIELDS=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    usage = data.get('usage') or (data.get('tool_response') or {}).get('usage') or data.get('tool_response') or {}
    if not isinstance(usage, dict):
        usage = {}
    inp = int(usage.get('input_tokens', 0) or 0)
    cw = int(usage.get('cache_creation_input_tokens', 0) or 0)
    cr = int(usage.get('cache_read_input_tokens', 0) or 0)
    out = int(usage.get('output_tokens', 0) or 0)
    print(f'{inp} {cw} {cr} {out}')
except Exception:
    print('0 0 0 0')
" 2>/dev/null || echo "0 0 0 0")

  read USAGE_INPUT USAGE_CACHE_WRITE USAGE_CACHE_READ USAGE_OUTPUT <<< "$USAGE_FIELDS"

  # If all zero, nothing to accumulate — exit cleanly
  TOTAL_TOKENS=$((USAGE_INPUT + USAGE_CACHE_WRITE + USAGE_CACHE_READ + USAGE_OUTPUT))
  if [ "$TOTAL_TOKENS" -eq 0 ]; then
    echo "[Supercharger] budget-cap: no usage data in payload — skipping" >&2
    exit 0
  fi

  # Read existing state or start fresh
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Detect model from payload to pick the right price tier. Falls back to
  # SUPERCHARGER_PRICING_MODEL env var, then Sonnet 4.6.
  PAYLOAD_MODEL=$( (printf '%s\n' "$_INPUT" | grep -oE '"model"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/') 2>/dev/null || true)

  COST_INPUT="$COST_FILE" \
  USAGE_INPUT="$USAGE_INPUT" USAGE_CACHE_WRITE="$USAGE_CACHE_WRITE" \
  USAGE_CACHE_READ="$USAGE_CACHE_READ" USAGE_OUTPUT="$USAGE_OUTPUT" \
  NOW="$NOW" \
  PAYLOAD_MODEL="$PAYLOAD_MODEL" \
  PRICING_OVERRIDE="${SUPERCHARGER_PRICING_MODEL:-}" \
  python3 << 'PYEOF' > "$COST_TMP"
import json, os

cost_file = os.environ['COST_INPUT']
now = os.environ['NOW']

# Pricing tiers (June 2026) — input / cache_write_5min / cache_read / output per MTok.
# Cache write 5min is 1.25× input; cache read is 0.10× input (Anthropic standard).
# Sources: cloudzero.com/blog/claude-api-pricing, devtk.ai/en/blog/claude-api-pricing-guide-2026
PRICING = {
    'opus':   (5.00,  6.25, 0.50, 25.00),
    'sonnet': (3.00,  3.75, 0.30, 15.00),
    'haiku':  (0.80,  1.00, 0.08,  4.00),
}

model = (os.environ.get('PAYLOAD_MODEL') or '').lower()
override = (os.environ.get('PRICING_OVERRIDE') or '').lower()
if override in PRICING:
    tier = override
elif 'opus' in model:
    tier = 'opus'
elif 'haiku' in model:
    tier = 'haiku'
else:
    tier = 'sonnet'
in_p, cw_p, cr_p, out_p = PRICING[tier]

inp = int(os.environ.get('USAGE_INPUT', 0) or 0)
cw  = int(os.environ.get('USAGE_CACHE_WRITE', 0) or 0)
cr  = int(os.environ.get('USAGE_CACHE_READ', 0) or 0)
out = int(os.environ.get('USAGE_OUTPUT', 0) or 0)
turn_cost = (inp * in_p + cw * cw_p + cr * cr_p + out * out_p) / 1_000_000

# Load existing state
state = {}
if os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            state = json.load(f)
    except Exception:
        state = {}

prev_total = float(state.get('total_usd', 0) or 0)
prev_turns = int(state.get('turn_count', 0) or 0)
prev_subagent = float(state.get('subagent_total', 0) or 0)
first_updated = state.get('first_updated', '')

new_total = prev_total + turn_cost
new_turns = prev_turns + 1
avg = new_total / new_turns if new_turns > 0 else 0.0

if not first_updated:
    first_updated = now

result = {
    'total_usd': round(new_total, 8),
    'turn_count': new_turns,
    'avg_per_turn': round(avg, 8),
    'first_updated': first_updated,
    'last_updated': now,
    'subagent_total': round(prev_subagent, 8)
}
print(json.dumps(result))
PYEOF

  # Atomic move
  mv "$COST_TMP" "$COST_FILE"

  echo "[Supercharger] budget-cap: accumulated file=$COST_FILE" >&2
  exit 0
fi

# ── check (PreToolUse) ────────────────────────────────────────────────────────
if [[ "$MODE" == "check" ]]; then
  _INPUT=$(cat)

  # Bash fast-path: skip the python3 fork entirely when no budget cap is
  # configured (the common case — most users don't set one). Walks up at most
  # 5 levels for .supercharger.json and greps for a "budget" key. ~5ms vs the
  # ~70ms python3 cold-start it replaces.
  if [ -z "${SESSION_BUDGET_CAP:-}" ]; then
    # || true: pipefail must not abort when cwd field is absent
    _SEARCH_DIR=$( (printf '%s\n' "$_INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/') 2>/dev/null || true)
    [ -z "$_SEARCH_DIR" ] && _SEARCH_DIR="$PWD"
    # v2.6.36: if we're in a linked worktree, .supercharger.json lives in the
    # main repo. Resolve to that before walking.
    _SEARCH_DIR=$(_resolve_project_root "$_SEARCH_DIR")
    _HAS_CAP=0
    for _ in 1 2 3 4 5; do
      if [ -f "$_SEARCH_DIR/.supercharger.json" ]; then
        if grep -q '"budget"' "$_SEARCH_DIR/.supercharger.json" 2>/dev/null; then
          _HAS_CAP=1
        fi
        break
      fi
      _PARENT=$(dirname "$_SEARCH_DIR")
      [ "$_PARENT" = "$_SEARCH_DIR" ] && break
      _SEARCH_DIR="$_PARENT"
    done
    [ "$_HAS_CAP" -eq 0 ] && exit 0
  fi

  # Single python3 fork: parse stdin, walk up for .supercharger.json, read
  # .session-cost, evaluate threshold.
  # v2.6.36: pre-resolved worktree-aware root passed via env; python uses it as
  # walk start instead of the raw cwd from the payload.
  _CWD_FROM_PAYLOAD=$( (printf '%s\n' "$_INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/') 2>/dev/null || true)
  [ -z "$_CWD_FROM_PAYLOAD" ] && _CWD_FROM_PAYLOAD="$PWD"
  PROJECT_ROOT=$(_resolve_project_root "$_CWD_FROM_PAYLOAD")
  DECISION=$(SESSION_BUDGET_CAP="${SESSION_BUDGET_CAP:-}" COST_FILE="$COST_FILE" HOOK_INPUT="$_INPUT" PROJECT_ROOT="$PROJECT_ROOT" python3 <<'PYEOF'
import json, os, sys

try:
    data = json.loads(os.environ.get('HOOK_INPUT', '{}'))
except Exception:
    print('pass'); sys.exit(0)

tool = (data.get('tool_name') or '').strip()
# v2.6.36: walk from worktree-aware root, not raw cwd
cwd = os.environ.get('PROJECT_ROOT') or data.get('cwd') or os.environ.get('PWD', '/')

cap = ''
env_cap = os.environ.get('SESSION_BUDGET_CAP', '')
if env_cap:
    cap = env_cap
else:
    # Walk up to find .supercharger.json
    d = cwd
    for _ in range(5):
        cfg = os.path.join(d, '.supercharger.json')
        if os.path.isfile(cfg):
            try:
                with open(cfg) as f:
                    cap = str(json.load(f).get('budget', '') or '')
            except Exception:
                cap = ''
            break
        parent = os.path.dirname(d)
        if parent == d: break
        d = parent

if not cap:
    print('pass'); sys.exit(0)

try:
    cap_f = float(cap)
except Exception:
    print('pass'); sys.exit(0)

spend = 0.0
cost_file = os.environ.get('COST_FILE', '')
if cost_file and os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            spend = float(json.load(f).get('total_usd', 0) or 0)
    except Exception:
        spend = 0.0

pct = (spend / cap_f * 100) if cap_f > 0 else 0
READ_ONLY = {'Read', 'Glob', 'Grep'}

if pct >= 100:
    if tool in READ_ONLY:
        print('pass')
    else:
        print(f'block:Session budget cap reached: ${spend:.4f} spent of ${cap_f:.2f} cap ({pct:.0f}%). Use read-only tools or start a new session.')
elif pct >= 80:
    print(f'warn:[BUDGET] {pct:.0f}% of session cap used (${spend:.4f} / ${cap_f:.2f}). Consider wrapping up.')
else:
    print('pass')
PYEOF
)
  if [[ "$DECISION" == "pass" ]]; then
    exit 0
  elif [[ "$DECISION" == warn:* ]]; then
    MSG="${DECISION#warn:}"
    echo "[Supercharger] budget-cap: warning — $MSG" >&2
    CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$MSG")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
    exit 0
  elif [[ "$DECISION" == block:* ]]; then
    REASON="${DECISION#block:}"
    echo "[Supercharger] budget-cap: BLOCKING — $REASON" >&2
    REASON_JSON=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$REASON")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$REASON_JSON"
    exit 2
  fi

  exit 0
fi

exit 0
