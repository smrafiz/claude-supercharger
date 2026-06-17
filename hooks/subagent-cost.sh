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

  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
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

agent_id = (d.get('agent_id') or '') or 'unknown-' + pid
agent_name = (d.get('agent_name') or '') or (d.get('name') or '') or 'agent'
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
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
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

agent_id   = (d.get('agent_id') or '') or 'unknown'
agent_name = (d.get('agent_name') or '') or (d.get('name') or '') or 'agent'
session_id = (d.get('session_id') or '') or 'default'

u = d.get('usage') or {}
def _i(v):
    try:    return int(v or 0)
    except Exception: return 0
input_tok   = _i(u.get('input_tokens'))
cache_write = _i(u.get('cache_creation_input_tokens'))
cache_read  = _i(u.get('cache_read_input_tokens'))
output_tok  = _i(u.get('output_tokens'))

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
payload_model = (d.get('model') or '').lower()
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

# Append to JSONL log
jsonl_file = os.path.join(scope_dir, f'.subagent-costs-{session_id}.jsonl')
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
try:
    with open(jsonl_file, 'a') as f:
        f.write(json.dumps(entry) + '\n')
except Exception:
    pass

# Update .session-cost atomically (write tmp then rename)
cost_file = os.path.join(scope_dir, '.session-cost')
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
new_total = prev_total + turn_cost
new_subagent = prev_subagent + turn_cost
avg = new_total / prev_turns if prev_turns > 0 else 0.0
new_state = {
    'total_usd': round(new_total, 8),
    'turn_count': prev_turns,
    'avg_per_turn': round(avg, 8),
    'first_updated': first_updated,
    'last_updated': now,
    'subagent_total': round(new_subagent, 8),
}
tmp_file = cost_file + f'.{os.getpid()}.tmp'
try:
    with open(tmp_file, 'w') as f:
        json.dump(new_state, f)
    os.rename(tmp_file, cost_file)
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
