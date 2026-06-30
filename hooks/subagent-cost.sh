#!/usr/bin/env bash
# Claude Supercharger — Subagent Cost Tracker
# Event: SubagentStart,SubagentStop | Matcher: (none)
# Modes:
#   start — records agent start time asynchronously
#   stop  — calculates cost, logs to JSONL, updates session-cost, injects summary

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

MODE="${1:-start}"

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

# ── Start (SubagentStart) ─────────────────────────────────────────────────────
if [[ "$MODE" == "start" ]]; then
  _INPUT=$(cat)

  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  init_hook_suppress "$PROJECT_DIR"

  # v2.6.22: one python3 fork does parse + extract + timestamp + write.
  # Was: 1 jq + 4 python3 forks (agent_id, agent_name, NOW, then bash printf).
  # Returns agent_id and agent_name on two stdout lines for the stderr log.
  RESULT=$(HOOK_INPUT="$_INPUT" SCOPE_DIR="$SCOPE_DIR" PID="$$" python3 <<'PYEOF' 2>/dev/null
import json, os, sys
from datetime import datetime, timezone

raw = os.environ.get('HOOK_INPUT', '')
scope_dir = os.environ.get('SCOPE_DIR', '')
pid = os.environ.get('PID', '0')

try:
    d = json.loads(raw)
except Exception:
    d = {}

# v2.7.11: SubagentStart uses subagent_id/subagent_type; SubagentStop uses
# agent_id/agent_type. Read both spellings so START and STOP key the active file
# by the SAME id — otherwise the stop-side start-time lookup always misses and
# duration is always 0.
agent_id = (d.get('agent_id') or d.get('subagent_id') or '') or 'unknown-' + pid
agent_name = (d.get('agent_name') or d.get('agent_type') or d.get('subagent_type') or d.get('name') or '') or 'agent'
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

if scope_dir:
    active_file = os.path.join(scope_dir, '.subagent-active-' + agent_id)
    try:
        with open(active_file, 'w') as f:
            json.dump({'agent_id': agent_id, 'name': agent_name, 'started_at': now}, f)
    except Exception:
        pass

print(agent_id)
print(agent_name)
PYEOF
)
  AGENT_ID=$(printf '%s' "$RESULT" | sed -n '1p')
  AGENT_NAME=$(printf '%s' "$RESULT" | sed -n '2p')
  [ -z "$AGENT_ID" ] && AGENT_ID="unknown-$$"
  [ -z "$AGENT_NAME" ] && AGENT_NAME="agent"

  echo "[Supercharger] subagent-cost: start recorded for agent=$AGENT_ID name=$AGENT_NAME" >&2
  exit 0
fi

# ── Stop (SubagentStop) ───────────────────────────────────────────────────────
if [[ "$MODE" == "stop" ]]; then
  _INPUT=$(cat)

  # v2.6.23: one python3 fork does everything for stop mode. Was 12 forks
  # (1 for cwd, 1 for agent fields, 2 for active-file reads, 1 for NOW, 1 for
  # DURATION, 1 for cost, 1 for tokens fmt, 1 for cost fmt, 1 for JSONL entry,
  # 1 for session-cost update, 1 for systemMessage JSON wrap). Now: 1 python3
  # heredoc parses stdin + reads active file + computes durations + writes
  # JSONL + atomically updates session-cost + emits final hookSpecificOutput.
  # Cwd extraction stays a separate jq for the init_hook_suppress call below.
  # Median 100ms → ~30ms (-70%).
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  init_hook_suppress "$PROJECT_DIR"

  STOP_OUT=$(HOOK_INPUT="$_INPUT" SCOPE_DIR="$SCOPE_DIR" \
             PRICING_OVERRIDE="${SUPERCHARGER_PRICING_MODEL:-}" \
             python3 <<'PYEOF' 2>/dev/null
import json, os, sys
from datetime import datetime, timezone

raw = os.environ.get('HOOK_INPUT', '')
scope_dir = os.environ.get('SCOPE_DIR', '')

try:
    d = json.loads(raw)
except Exception:
    d = {}

# v2.7.11: CC's SubagentStop payload uses agent_id/agent_type and carries NO
# usage field (confirmed CC 2.1.181). Read both key spellings; recover real token
# usage from agent_transcript_path since the payload omits it.
agent_id   = (d.get('agent_id') or d.get('subagent_id') or '') or 'unknown'
agent_name = (d.get('agent_name') or d.get('agent_type') or d.get('subagent_type') or d.get('name') or '') or 'agent'
session_id = (d.get('session_id') or '') or 'default'

def _i(v):
    try:    return int(v or 0)
    except Exception: return 0

u = d.get('usage') or {}
input_tok   = _i(u.get('input_tokens'))
cache_write = _i(u.get('cache_creation_input_tokens'))
cache_read  = _i(u.get('cache_read_input_tokens'))
output_tok  = _i(u.get('output_tokens'))

# Fallback: sum per-message usage from the subagent transcript when the payload
# has none (the normal case). Each assistant message = one billed API call, so
# summing input/cache/output across messages is the correct cost basis. Also
# captures the model for pricing (payload has no model field either).
transcript_model = ''
if not (input_tok or cache_write or cache_read or output_tok):
    tpath = d.get('agent_transcript_path') or d.get('transcript_path') or ''
    if tpath and os.path.isfile(tpath):
        try:
            with open(tpath) as tf:
                for line in tf:
                    try:    td = json.loads(line)
                    except Exception: continue
                    msg = td.get('message') or {}
                    mu = msg.get('usage') or td.get('usage') or {}
                    if not mu:
                        continue
                    input_tok   += _i(mu.get('input_tokens'))
                    cache_write += _i(mu.get('cache_creation_input_tokens'))
                    cache_read  += _i(mu.get('cache_read_input_tokens'))
                    output_tok  += _i(mu.get('output_tokens'))
                    transcript_model = transcript_model or (msg.get('model') or td.get('model') or '')
        except Exception:
            pass

# Read start record
started_at = ''
active_file = os.path.join(scope_dir, '.subagent-active-' + agent_id)
if os.path.isfile(active_file):
    try:
        with open(active_file) as f:
            ad = json.load(f)
        started_at = ad.get('started_at', '') or ''
        if agent_name == 'agent':
            agent_name = ad.get('name', 'agent') or 'agent'
    except Exception:
        pass

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

duration_s = 0
if started_at:
    try:
        started = datetime.fromisoformat(started_at.replace('Z', '+00:00'))
        stopped = datetime.fromisoformat(now.replace('Z', '+00:00'))
        duration_s = int(max(0, (stopped - started).total_seconds()))
    except Exception:
        pass

# Pricing tiers (June 2026) per MTok: input / cache_write_5min / cache_read / output.
# Sources: cloudzero.com/blog/claude-api-pricing. Model detected from payload
# `model` field if present; falls back to SUPERCHARGER_PRICING_MODEL env var,
# then Sonnet 4.6.
PRICING = {
    'opus':   (5.00, 6.25, 0.50, 25.00),
    'sonnet': (3.00, 3.75, 0.30, 15.00),
    'haiku':  (0.80, 1.00, 0.08,  4.00),
}
payload_model = (d.get('model') or transcript_model or '').lower()
override = (os.environ.get('PRICING_OVERRIDE') or '').lower()
if override in PRICING:
    tier = override
elif 'opus' in payload_model:
    tier = 'opus'
elif 'haiku' in payload_model:
    tier = 'haiku'
else:
    tier = 'sonnet'
in_p, cw_p, cr_p, out_p = PRICING[tier]
turn_cost = (input_tok * in_p + cache_write * cw_p + cache_read * cr_p + output_tok * out_p) / 1_000_000
total_tokens = input_tok + cache_write + cache_read + output_tok

# Format
if total_tokens >= 1_000_000:
    tokens_fmt = f'{total_tokens/1_000_000:.1f}M'
elif total_tokens >= 1_000:
    tokens_fmt = f'{total_tokens/1_000:.0f}K'
else:
    tokens_fmt = str(total_tokens)
cost_fmt = f'${turn_cost:.2f}'

# Delete start record
try:
    if os.path.isfile(active_file):
        os.remove(active_file)
except Exception:
    pass

# v2.7.13: UPSERT one row per agent_id, last-cumulative-wins. CC re-fires
# SubagentStop repeatedly (stop_hook_active re-entry) — observed ~10x for one
# agent — and each firing carries the CUMULATIVE transcript total. Appending
# every time over-counted the rollup ~7-10x once entries became nonzero (v2.7.11).
# Drop any prior row for this agent and write the latest; add only the DELTA to
# the session aggregate below. Carry forward the real duration (the first stop
# captures it; re-fires find no active file and compute 0).
jsonl_file = os.path.join(scope_dir, f'.subagent-costs-{session_id}.jsonl')
prev_cost = 0.0
prev_duration = 0.0
prev_entry = None
kept_lines = []
if os.path.isfile(jsonl_file):
    try:
        with open(jsonl_file) as f:
            for line in f:
                line = line.rstrip('\n')
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    kept_lines.append(line)
                    continue
                if row.get('agent_id') == agent_id:
                    rc = float(row.get('cost_usd', 0) or 0)
                    if prev_entry is None or rc >= prev_cost:
                        prev_entry = row
                    prev_cost = max(prev_cost, rc)
                    prev_duration = max(prev_duration, float(row.get('duration_s', 0) or 0))
                else:
                    kept_lines.append(line)
    except Exception:
        kept_lines = []

if duration_s == 0 and prev_duration > 0:
    duration_s = prev_duration

# v2.7.20: a later SubagentStop re-fire can arrive AFTER the agent's transcript
# was cleaned up → it computes $0 / "agent" fallback name and would clobber the
# good earlier recording. Keep the richer prior row when this firing is weaker
# (cost not higher); only overwrite when we have MORE cost than before.
if prev_entry is not None and turn_cost <= prev_cost:
    entry = dict(prev_entry)
    entry['stopped_at'] = now
    if float(duration_s) > float(entry.get('duration_s', 0) or 0):
        entry['duration_s'] = float(duration_s)
else:
    entry = {
        'agent_id': agent_id,
        'agent_name': agent_name,
        'session_id': session_id,
        'started_at': started_at,
        'stopped_at': now,
        'duration_s': float(duration_s),
        'input_tokens': input_tok,
        'cache_write_tokens': cache_write,
        'cache_read_tokens': cache_read,
        'output_tokens': output_tok,
        'total_tokens': total_tokens,
        'cost_usd': float(turn_cost),
    }
kept_lines.append(json.dumps(entry))
try:
    tmp_jsonl = jsonl_file + f'.{os.getpid()}.tmp'
    with open(tmp_jsonl, 'w') as f:
        f.write('\n'.join(kept_lines) + '\n')
    os.rename(tmp_jsonl, jsonl_file)
except Exception:
    pass

# Only the incremental cost since this agent's last logged value feeds the
# session aggregate — so re-fires don't inflate it.
cost_delta = max(0.0, turn_cost - prev_cost)

# Update .session-cost. v2.7.16: the read-modify-write is shared with budget-cap
# (async PostToolUse) — without a lock, concurrent invocations both read the same
# prev value and the last rename wins, dropping the other's delta. fcntl.flock
# (portable across macOS+Linux, unlike the `flock` shell util) serializes the
# whole RMW. The atomic rename already prevented corruption; this prevents lost
# updates.
cost_file = os.path.join(scope_dir, '.session-cost')
import fcntl
lock_file = cost_file + '.lock'
_lf = None
try:
    _lf = open(lock_file, 'w')
    fcntl.flock(_lf, fcntl.LOCK_EX)
except Exception:
    _lf = None
try:
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
    first_updated = state.get('first_updated', '') or now
    new_total = prev_total + cost_delta
    new_subagent = prev_subagent + cost_delta
    avg = new_total / prev_turns if prev_turns > 0 else 0.0
    new_state = {
        'total_usd': round(new_total, 8),
        'turn_count': prev_turns,
        'avg_per_turn': round(avg, 8),
        'first_updated': first_updated,
        'last_updated': now,
        'subagent_total': round(new_subagent, 8),
    }
    # v2.7.15: preserve budget-cap's main-loop tracking fields (it keys off these
    # to compute its incremental delta — dropping them would double-count main cost).
    if 'main_total' in state:
        new_state['main_total'] = state['main_total']
    if 'main_offset' in state:
        new_state['main_offset'] = state['main_offset']
    tmp_file = cost_file + f'.{os.getpid()}.tmp'
    try:
        with open(tmp_file, 'w') as f:
            json.dump(new_state, f)
        os.rename(tmp_file, cost_file)
    except Exception:
        pass
finally:
    if _lf is not None:
        try:
            fcntl.flock(_lf, fcntl.LOCK_UN)
            _lf.close()
        except Exception:
            pass

# Emit hookSpecificOutput JSON for Claude
summary = f'[AGENT] {agent_name} completed: ~{cost_fmt} ({tokens_fmt} tokens, {duration_s}s)'
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SubagentStop',
        'additionalContext': summary,
    }
}))
# Stderr line for the bash log
sys.stderr.write(f'[Supercharger] subagent-cost: stop recorded agent={agent_id} cost={turn_cost:.8f} duration={duration_s}s\n')
PYEOF
)
  [ -n "$STOP_OUT" ] && printf '%s\n' "$STOP_OUT"
  exit 0
fi

exit 0
