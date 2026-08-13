#!/usr/bin/env bash
# Claude Supercharger — Budget Cap Hook
# Event: PostToolUse (accumulator) | PreToolUse check (blocker) | Matcher: (none)
# Modes:
#   (no arg)  — PostToolUse accumulator: reads token usage, calculates cost, writes .session-cost
#   check     — PreToolUse blocker: reads .session-cost, warns at 80%, blocks at 100%

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh" 2>/dev/null || true

# v2.24.0: read `cwd` without a fork. This hook has an EMPTY matcher, so it fires on
# every tool call (Bash, Read, Grep, Edit…) and the old 4-fork pipeline
# (printf|grep -oE|head|sed -E) was paid every time. lib-json-fast refuses anything
# ambiguous/escaped, so the original pipeline stays as the fallback.
_bc_cwd() {   # -> echoes cwd (payload value, else $PWD)
  if command -v _json_fast_str >/dev/null 2>&1 && _json_fast_str cwd "$_INPUT"; then
    printf '%s' "$_JSON_FAST_VAL"; return 0
  fi
  local v
  v=$( (printf '%s\n' "$_INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/') 2>/dev/null || true)
  [ -z "$v" ] && v="$PWD"
  printf '%s' "$v"
}

MODE="${1:-accumulate}"

SUPERCHARGER_DIR="$SUPERCHARGER_STATE"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
# v2.24.0: `mkdir -p` forks on every fire even though the dir almost always exists,
# and check-mode never creates anything. Test first — the fork is the expensive part.
[ -d "$SCOPE_DIR" ] || mkdir -p "$SCOPE_DIR"

COST_FILE="$SCOPE_DIR/.session-cost"
COST_TMP="$SCOPE_DIR/.session-cost.$$.tmp"

# ── accumulate (PostToolUse) ───────────────────────────────────────────────────
if [[ "$MODE" == "accumulate" ]]; then
  # v2.26.80: fork-free stdin read. This hook was missed by v2.26.35, which removed
  # the /bin/cat fork from every other hook — and `check` is the single most
  # expensive hook on the Bash PreToolUse chain, so it was the worst place to
  # leave one. Byte-identical to $(cat): the trailing strip reproduces its
  # newline handling.
  IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

  # v2.7.15: CC's PostToolUse payload carries NO token usage (verified: tool_response
  # = {interrupted,isImage,noOutputExpected,stderr,stdout}), so the old payload-usage
  # read was always 0 → the budget cap never accumulated and never enforced. The
  # payload DOES carry `transcript_path`; each assistant message's `usage` is one
  # billed API call. We INCREMENTALLY sum only the messages past a stored byte
  # offset (O(new lines), not O(whole transcript) per call) and add that delta to
  # the running total — keyed separately from subagent cost so neither clobbers
  # the other (each adds its own delta; the invariant total_usd == main_total +
  # subagent_total holds).
  # v2.23.2: fork-free transcript_path extraction (was a jq fork). Falls back to
  # jq only if the fast parse misses (e.g. non-compact JSON) — so the common
  # compact-payload case pays no fork, without regressing correctness.
  _TP_AFTER="${_INPUT#*\"transcript_path\":\"}"
  if [ "$_TP_AFTER" = "$_INPUT" ]; then
    # fast parse missed (non-compact JSON) — fall back to jq for correctness.
    TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  else
    TRANSCRIPT="${_TP_AFTER%%\"*}"
  fi
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
  fi

  # v2.23.2: debounce the transcript walk — the single largest hook cost in
  # profiling (~65s/session; ~237ms/call from the python cold-start). The walk
  # resumes from a persisted PER-TRANSCRIPT byte offset (incremental + additive),
  # so deferring it loses NO tokens — only statusline/cap freshness within the
  # window. Skipping the majority of PostToolUse calls removes the python fork
  # entirely on those calls. Default 4s; set SUPERCHARGER_BUDGET_DEBOUNCE_SECS=0
  # for exact per-call accounting (e.g. a tight cap where <window overshoot
  # matters). Cost of the gate itself: one `date +%s` fork; the marker read/write
  # are bash builtins (no fork). Marker is keyed per-transcript so concurrent
  # sessions never debounce each other's walk.
  _DEBOUNCE="${SUPERCHARGER_BUDGET_DEBOUNCE_SECS:-4}"
  case "$_DEBOUNCE" in ''|*[!0-9]*) _DEBOUNCE=4 ;; esac
  if [ "$_DEBOUNCE" -gt 0 ]; then
    _NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
    _TKEY="${TRANSCRIPT##*/}"; _TKEY="${_TKEY%.jsonl}"
    case "$_TKEY" in ''|*[!A-Za-z0-9._-]*) _TKEY="global" ;; esac
    _WALK_TS="$SCOPE_DIR/.budget-walk-$_TKEY"
    _LAST_WALK=0
    if [ -f "$_WALK_TS" ]; then read -r _LAST_WALK < "$_WALK_TS" 2>/dev/null || true; fi
    case "$_LAST_WALK" in ''|*[!0-9]*) _LAST_WALK=0 ;; esac
    if [ "$_NOW_EPOCH" -gt 0 ] && [ "$_LAST_WALK" -gt 0 ] \
       && [ $(( _NOW_EPOCH - _LAST_WALK )) -lt "$_DEBOUNCE" ]; then
      exit 0
    fi
    [ "$_NOW_EPOCH" -gt 0 ] && printf '%s\n' "$_NOW_EPOCH" > "$_WALK_TS" 2>/dev/null || true
  fi

  # v2.23.2: session_id passed RAW (sanitized in python) — was a jq+tr+head fork
  # chain; `now` is computed in python — was a `date -u` fork. Same fast-parse +
  # jq-fallback shape as transcript_path above.
  _SID_AFTER="${_INPUT#*\"session_id\":\"}"
  if [ "$_SID_AFTER" = "$_INPUT" ]; then
    SESSION_ID_RAW=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  else
    SESSION_ID_RAW="${_SID_AFTER%%\"*}"
  fi
  COST_INPUT="$COST_FILE" TRANSCRIPT="$TRANSCRIPT" \
  PRICING_OVERRIDE="${SUPERCHARGER_PRICING_MODEL:-}" \
  SESSION_ID_RAW="$SESSION_ID_RAW" SCOPE_DIR="$SCOPE_DIR" \
  COST_TMP="$COST_TMP" python3 << 'PYEOF' || exit 0
import json, os, time, datetime, re

# v2.26.73: fcntl does not exist on Windows python. Imported unconditionally, the
# ModuleNotFoundError killed this whole block before it wrote anything — so on Git
# Bash the per-session token file was never created (statusline showed `main 0`)
# and, far worse, THE BUDGET CAP NEVER RAN. A cost guard that silently does nothing
# is the worst failure mode available to it. Reported from a real Windows desktop.
#
# Degrading to no lock is safe rather than a compromise: the acquire below is
# already bounded and falls through to a best-effort unlocked write after ~2s, so
# this simply takes a path the code has always tolerated. os.replace stays atomic.
try:
    import fcntl
except ImportError:
    fcntl = None

cost_file = os.environ['COST_INPUT']
transcript = os.environ['TRANSCRIPT']
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

PRICING = {
    'opus':   (5.00,  6.25, 0.50, 25.00),
    'sonnet': (3.00,  3.75, 0.30, 15.00),
    'haiku':  (0.80,  1.00, 0.08,  4.00),
    'fable':  (10.00, 12.50, 1.00, 50.00),  # v2.9.3: Fable/Mythos 5 = 2x Opus; without this they'd fall to the sonnet fallback and be priced ~3x too LOW (budget cap overruns)
}
override = (os.environ.get('PRICING_OVERRIDE') or '').lower()

# v2.7.16: serialize the whole read-modify-write — shared with subagent-cost via
# fcntl.flock (portable; macOS has no `flock` shell util). Without it concurrent
# async writers drop each other's delta. Hold across the (incremental) transcript
# read since the byte offset we resume from lives in cost_file.
_lf = None
try:
    _lf = open(cost_file + '.lock', 'w')
    # v2.7.51: bounded acquire — NEVER block forever. budget-cap runs on every
    # PostToolUse; an alive-but-stuck lock holder would otherwise hang every
    # subsequent tool call (the kernel releases flock when a holder DIES, but not
    # when it's merely wedged). Try non-blocking for ~2s, then proceed best-effort
    # without the lock — a rare lost delta under real contention beats a permanent
    # session hang. Uncontended acquire still succeeds on the first try.
    _deadline = time.time() + 2.0
    while fcntl is not None:   # no fcntl (Windows) -> the unlocked path below
        try:
            fcntl.flock(_lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except (BlockingIOError, OSError):
            if time.time() >= _deadline:
                break  # give up the lock, proceed best-effort
            time.sleep(0.02)
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
# v2.7.47: the resume byte-offset is PER-TRANSCRIPT (per session), not one global
# int. A single shared offset let concurrent sessions — each with its OWN
# transcript_path — ping-pong it: session B (small transcript) would rewind the
# offset, then session A (large transcript) re-read an already-counted region and
# ADD it again → runaway token/cost over-count. Key the offset by transcript path.
# Migrate any legacy single main_offset onto the active transcript so the first
# post-upgrade turn stays incremental instead of re-deriving.
offsets = state.get('main_offsets')
if not isinstance(offsets, dict):
    offsets = {}
    _legacy = int(state.get('main_offset', 0) or 0)
    if _legacy:
        offsets[transcript] = _legacy
offset        = int(offsets.get(transcript, 0) or 0)
first_updated = state.get('first_updated', '') or now

# v2.7.17: read the transcript in BINARY mode. Text-mode seek() does NOT accept
# hand-counted byte offsets (only opaque f.tell() cookies), so the previous
# `new_offset += len(line.encode())` arithmetic drifted, overshot the real file
# size, tripped the reset-to-0 below, and re-summed the WHOLE transcript every
# call → runaway ~3.8x over-count. Binary readline()/tell() give true byte
# positions that seek() honors. If the offset is past EOF (shrink/rotation OR a
# legacy corrupt offset), reset BOTH the offset and main_total so we re-derive
# main cost cleanly instead of adding to an already-inflated value.
try:
    size = os.path.getsize(transcript)
except Exception:
    size = 0
reset = False
if offset > size:
    offset = 0
    prev_main = 0.0
    prev_turns = 0   # re-derive main turn count from the full re-read
    reset = True     # v2.7.36: also re-derive the per-session token total

def _i(v):
    try:    return int(v or 0)
    except Exception: return 0

delta_cost = 0.0
delta_tokens = 0   # v2.7.36: parent NEW tokens (input + cache_write + output)
new_msgs = 0
new_offset = offset
try:
    with open(transcript, 'rb') as f:
        f.seek(offset)
        while True:
            bline = f.readline()
            if not bline:
                break
            new_offset = f.tell()
            try:
                d = json.loads(bline.decode('utf-8', 'replace'))
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
            elif 'fable' in model or 'mythos' in model:
                tier = 'fable'
            elif 'haiku' in model:
                tier = 'haiku'
            else:
                tier = 'sonnet'
            in_p, cw_p, cr_p, out_p = PRICING[tier]
            delta_cost += (_i(u.get('input_tokens')) * in_p
                           + _i(u.get('cache_creation_input_tokens')) * cw_p
                           + _i(u.get('cache_read_input_tokens')) * cr_p
                           + _i(u.get('output_tokens')) * out_p) / 1_000_000
            # v2.7.39: CONTENT tokens = input + output only (exclude ALL cache —
            # both cache_read re-reads AND cache_write). Matches the sub display.
            delta_tokens += (_i(u.get('input_tokens')) + _i(u.get('output_tokens')))
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
}
# v2.7.47: persist the per-transcript offset map. Prune entries whose transcript
# file is gone, and bound the map so it can't grow without limit.
offsets[transcript] = new_offset
offsets = {k: v for k, v in offsets.items() if k and os.path.isfile(k)}
if len(offsets) > 40:
    offsets = {transcript: new_offset}
result['main_offsets'] = offsets
# Write atomically (tmp + rename) inside the lock, then release.
tmp = os.environ.get('COST_TMP') or (cost_file + '.tmp')
try:
    with open(tmp, 'w') as f:
        json.dump(result, f)
    os.replace(tmp, cost_file)
except Exception:
    try: os.remove(tmp)
    except Exception: pass
finally:
    if _lf is not None:
        try:
            if fcntl is not None:
                fcntl.flock(_lf, fcntl.LOCK_UN)
            _lf.close()
        except Exception:
            pass

# v2.7.36: per-session parent NEW-token running total (input + cache_write +
# output, excl cache_read — same basis as the sub-token display), for the
# statusline's combined session-token metric. Keyed by session_id, separate from
# the machine-global cost file. `reset` mirrors the cost re-derive above so a
# transcript rotation re-derives instead of double-counting.
sid = re.sub(r'[^a-zA-Z0-9_-]', '', os.environ.get('SESSION_ID_RAW', ''))[:64]
if sid:
    tf = os.path.join(os.environ.get('SCOPE_DIR') or os.path.dirname(cost_file), '.main-tokens-' + sid)
    prev_tok = 0
    prev_cost = 0.0
    try:
        with open(tf) as f:
            _pd = json.load(f)
            prev_tok = int(_pd.get('new_tokens', 0) or 0)
            prev_cost = float(_pd.get('cost_usd', 0) or 0)
    except Exception:
        prev_tok = 0
        prev_cost = 0.0
    # reset OR a from-zero read (fresh session, or a post-upgrade session whose
    # offset isn't in the new map yet) means delta_tokens already IS the full
    # session total — use it directly instead of adding to a stale prev_tok.
    main_tok = delta_tokens if (reset or offset == 0) else prev_tok + delta_tokens
    # v2.7.63: accumulate PER-SESSION cost here too (same reset/offset==0 re-derive
    # rule) so the budget cap compares THIS session's spend, not the machine-global
    # lifetime .session-cost total (which never resets → would block every session
    # instantly once lifetime spend exceeds the cap).
    sess_cost = delta_cost if (reset or offset == 0) else prev_cost + delta_cost
    try:
        with open(tf + '.tmp', 'w') as f:
            json.dump({'new_tokens': main_tok, 'cost_usd': round(sess_cost, 8), 'updated': now}, f)
        os.replace(tf + '.tmp', tf)
    except Exception:
        pass
PYEOF

  echo "[Supercharger] budget-cap: accumulated (transcript-incremental) file=$COST_FILE" >&2
  exit 0
fi

# ── check (PreToolUse) ────────────────────────────────────────────────────────
if [[ "$MODE" == "check" ]]; then
  # v2.26.80: fork-free stdin read. This hook was missed by v2.26.35, which removed
  # the /bin/cat fork from every other hook — and `check` is the single most
  # expensive hook on the Bash PreToolUse chain, so it was the worst place to
  # leave one. Byte-identical to $(cat): the trailing strip reproduces its
  # newline handling.
  IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

  # Bash fast-path: skip the python3 fork entirely when no budget cap is
  # configured (the common case — most users don't set one). Walks up at most
  # 5 levels for .supercharger.json and greps for a "budget" key. ~5ms vs the
  # ~70ms python3 cold-start it replaces.
  if [ -z "${SESSION_BUDGET_CAP:-}" ]; then
    _SEARCH_DIR=$(_bc_cwd)
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
      # v2.24.0: ${v%/*} instead of $(dirname) — up to 5 forks saved per fire. The
      # payload cwd is absolute and unslashed, where the two agree; guard the root case.
      _PARENT="${_SEARCH_DIR%/*}"
      [ -z "$_PARENT" ] && _PARENT="/"
      [ "$_PARENT" = "$_SEARCH_DIR" ] && break
      _SEARCH_DIR="$_PARENT"
    done
    [ "$_HAS_CAP" -eq 0 ] && exit 0
  fi

  # Single python3 fork: parse stdin, walk up for .supercharger.json, read
  # .session-cost, evaluate threshold.
  # v2.6.36: pre-resolved worktree-aware root passed via env; python uses it as
  # walk start instead of the raw cwd from the payload.
  _CWD_FROM_PAYLOAD=$(_bc_cwd)
  [ -z "$_CWD_FROM_PAYLOAD" ] && _CWD_FROM_PAYLOAD="$PWD"
  PROJECT_ROOT=$(_resolve_project_root "$_CWD_FROM_PAYLOAD")
  DECISION=$(SESSION_BUDGET_CAP="${SESSION_BUDGET_CAP:-}" COST_FILE="$COST_FILE" SCOPE_DIR="$SCOPE_DIR" HOOK_INPUT="$_INPUT" PROJECT_ROOT="$PROJECT_ROOT" python3 <<'PYEOF'
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

# v2.7.63: budget is PER-SESSION — compare against THIS session's spend
# (.main-tokens-<sid> cost_usd), NOT the machine-global lifetime .session-cost
# total_usd (which never resets and would block every session instantly). A fresh
# session has no per-session file yet → spend 0 → pass, and "start a new session"
# in the block message now actually resets the count.
import re as _re
spend = 0.0
sid = _re.sub(r'[^a-zA-Z0-9_-]', '', str(data.get('session_id') or ''))[:64]
scope_dir = os.environ.get('SCOPE_DIR', '') or os.path.dirname(os.environ.get('COST_FILE', ''))
if sid and scope_dir:
    sf = os.path.join(scope_dir, '.main-tokens-' + sid)
    if os.path.isfile(sf):
        try:
            with open(sf) as f:
                spend = float(json.load(f).get('cost_usd', 0) or 0)
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
