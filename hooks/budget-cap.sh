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

  # v2.7.15: CC's PostToolUse payload carries NO token usage (verified: tool_response
  # = {interrupted,isImage,noOutputExpected,stderr,stdout}), so the old payload-usage
  # read was always 0 → the budget cap never accumulated and never enforced. The
  # payload DOES carry `transcript_path`; each assistant message's `usage` is one
  # billed API call. We INCREMENTALLY sum only the messages past a stored byte
  # offset (O(new lines), not O(whole transcript) per call) and add that delta to
  # the running total — keyed separately from subagent cost so neither clobbers
  # the other (each adds its own delta; the invariant total_usd == main_total +
  # subagent_total holds).
  TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
  fi

  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  COST_INPUT="$COST_FILE" TRANSCRIPT="$TRANSCRIPT" NOW="$NOW" \
  PRICING_OVERRIDE="${SUPERCHARGER_PRICING_MODEL:-}" \
  COST_TMP="$COST_TMP" python3 << 'PYEOF' || exit 0
import json, os, fcntl

cost_file = os.environ['COST_INPUT']
transcript = os.environ['TRANSCRIPT']
now = os.environ['NOW']

PRICING = {
    'opus':   (5.00,  6.25, 0.50, 25.00),
    'sonnet': (3.00,  3.75, 0.30, 15.00),
    'haiku':  (0.80,  1.00, 0.08,  4.00),
}
override = (os.environ.get('PRICING_OVERRIDE') or '').lower()

# v2.7.16: serialize the whole read-modify-write — shared with subagent-cost via
# fcntl.flock (portable; macOS has no `flock` shell util). Without it concurrent
# async writers drop each other's delta. Hold across the (incremental) transcript
# read since the byte offset we resume from lives in cost_file.
_lf = None
try:
    _lf = open(cost_file + '.lock', 'w')
    fcntl.flock(_lf, fcntl.LOCK_EX)
except Exception:
    _lf = None

state = {}
if os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            state = json.load(f)
    except Exception:
        state = {}

prev_total    = float(state.get('total_usd', 0) or 0)
prev_turns    = int(state.get('turn_count', 0) or 0)
prev_subagent = float(state.get('subagent_total', 0) or 0)
prev_main     = float(state.get('main_total', 0) or 0)
offset        = int(state.get('main_offset', 0) or 0)
first_updated = state.get('first_updated', '') or now

# Reset offset if the transcript shrank/rotated.
try:
    size = os.path.getsize(transcript)
except Exception:
    size = 0
if offset > size:
    offset = 0

def _i(v):
    try:    return int(v or 0)
    except Exception: return 0

delta_cost = 0.0
new_msgs = 0
new_offset = offset
try:
    with open(transcript) as f:
        f.seek(offset)
        for line in f:
            new_offset += len(line.encode('utf-8', 'replace'))
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get('type') != 'assistant':
                continue
            msg = d.get('message') or {}
            u = msg.get('usage') or {}
            if not u:
                continue
            model = (msg.get('model') or d.get('model') or '').lower()
            if override in PRICING:
                tier = override
            elif 'opus' in model:
                tier = 'opus'
            elif 'haiku' in model:
                tier = 'haiku'
            else:
                tier = 'sonnet'
            in_p, cw_p, cr_p, out_p = PRICING[tier]
            delta_cost += (_i(u.get('input_tokens')) * in_p
                           + _i(u.get('cache_creation_input_tokens')) * cw_p
                           + _i(u.get('cache_read_input_tokens')) * cr_p
                           + _i(u.get('output_tokens')) * out_p) / 1_000_000
            new_msgs += 1
except Exception:
    # On any read error, keep prior state unchanged.
    new_offset = offset

new_main  = prev_main + delta_cost
new_turns = prev_turns + new_msgs
new_total = new_main + prev_subagent
avg = new_total / new_turns if new_turns > 0 else 0.0

result = {
    'total_usd': round(new_total, 8),
    'turn_count': new_turns,
    'avg_per_turn': round(avg, 8),
    'first_updated': first_updated,
    'last_updated': now,
    'subagent_total': round(prev_subagent, 8),
    'main_total': round(new_main, 8),
    'main_offset': new_offset,
}
# Write atomically (tmp + rename) inside the lock, then release.
tmp = os.environ.get('COST_TMP') or (cost_file + '.tmp')
try:
    with open(tmp, 'w') as f:
        json.dump(result, f)
    os.rename(tmp, cost_file)
except Exception:
    try: os.remove(tmp)
    except Exception: pass
finally:
    if _lf is not None:
        try:
            fcntl.flock(_lf, fcntl.LOCK_UN)
            _lf.close()
        except Exception:
            pass
PYEOF

  echo "[Supercharger] budget-cap: accumulated (transcript-incremental) file=$COST_FILE" >&2
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
