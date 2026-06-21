#!/usr/bin/env bash
# Claude Supercharger — Subagent Lifecycle Discovery Hook
# Event: SubagentStart, SubagentStop | Matcher: *
#
# Subagent nesting now goes up to 5 levels deep (Claude Code v2.1.172).
# Top-level-only guardrails leak past the first nested agent. Before we
# design real per-depth budget caps and per-agent scope contracts, we need
# to know the actual payload shape: parent_agent_id, depth, subagent_type,
# allowed tools, model, prompt size, etc.
#
# Behavior: passthrough (exit 0). Never blocks.
# Storage: ~/.claude/supercharger/audit/subagent-payloads.jsonl  (capped at 10KB/entry)
# Disable: SUPERCHARGER_SUBAGENT_DISCOVERY=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_SUBAGENT_DISCOVERY:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "subagent-discovery" && exit 0

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR" 2>/dev/null || exit 0
LOG_FILE="$AUDIT_DIR/subagent-payloads.jsonl"

CAPPED=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys, datetime
raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    print(json.dumps({"error": "parse_failed", "raw_size": len(raw)}))
    sys.exit(0)

def trunc(v, lim=2000):
    if isinstance(v, str) and len(v) > lim:
        return v[:lim] + f'...[{len(v)-lim}b truncated]'
    if isinstance(v, dict):
        return {k: trunc(x, lim) for k, x in v.items()}
    if isinstance(v, list):
        return [trunc(x, lim) for x in v[:20]]
    return v

# Capture everything except tool_input bulk and message bodies; we want shape
# discovery, not transcript capture.
keep_keys = (
    'hook_event_name', 'session_id', 'subagent_id', 'subagent_type',
    'parent_agent_id', 'depth', 'nesting_depth', 'model', 'allowed_tools',
    'tools', 'description', 'prompt', 'task_id', 'reason', 'status',
)
record = {"ts": datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}
for k in keep_keys:
    if k in data:
        record[k] = trunc(data[k], 500 if k == 'prompt' else 2000)
# Also capture top-level key list so we learn unknown fields without dumping bodies.
record['_top_keys'] = sorted(data.keys())
print(json.dumps(record))
PYEOF
)
[ -z "$CAPPED" ] && exit 0
printf '%s\n' "$CAPPED" >> "$LOG_FILE" 2>/dev/null || true

echo "[Supercharger] subagent-discovery: logged payload to $LOG_FILE" >&2
exit 0
