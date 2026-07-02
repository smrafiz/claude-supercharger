#!/usr/bin/env bash
# Claude Supercharger — Elicitation Discovery Hook
# Event: Elicitation, ElicitationResult | Matcher: *
#
# Elicitation lets MCP servers solicit structured input from the user — a
# legitimate UX primitive (form fields, confirmation prompts) but also a
# direct vector for credential harvesting: a malicious or compromised MCP
# server can ask for an "API token", "GitHub PAT", "database password" in
# a form that looks routine. The blocking guard now lives in elicitation-guard.sh
# (v2.7.49): it declines credential-style fields from servers outside
# trustedElicitationServers. THIS hook is the async companion — it observes and
# logs every request's schema shape, server identity, and message length so the
# guard's heuristics can be tuned and post-incident review has a trail.
#
# Behavior: passthrough (exit 0). Never blocks — elicitation-guard.sh does that.
# Storage: ~/.claude/supercharger/audit/elicitation-payloads.jsonl
# Disable: SUPERCHARGER_ELICITATION_DISCOVERY=0
#
# We log metadata and schema *structure* but NOT user-typed values on the
# ElicitationResult event — those are by definition sensitive.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_ELICITATION_DISCOVERY:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "elicitation-discovery" && exit 0

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR" 2>/dev/null || exit 0
LOG_FILE="$AUDIT_DIR/elicitation-payloads.jsonl"

CAPPED=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys, datetime
raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    print(json.dumps({"error": "parse_failed", "raw_size": len(raw)}))
    sys.exit(0)

event = data.get('hook_event_name', '')

def schema_skeleton(s):
    if not isinstance(s, dict):
        return type(s).__name__
    out = {}
    for k, v in s.items():
        if isinstance(v, dict):
            out[k] = schema_skeleton(v)
        elif isinstance(v, list):
            out[k] = [schema_skeleton(x) if isinstance(x, dict) else type(x).__name__ for x in v[:5]]
        else:
            out[k] = type(v).__name__
    return out

record = {
    "ts": datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    "hook_event_name": event,
    "session_id": data.get("session_id", ""),
    "server_name": data.get("server_name", "") or data.get("mcp_server", "") or data.get("source", ""),
    "_top_keys": sorted(data.keys()),
}

# On Elicitation (the request): keep the schema structure — that tells us
# what fields the server is asking for. Strip values defensively.
if event == 'Elicitation':
    schema = data.get('schema') or data.get('requestedSchema') or data.get('elicitation_schema')
    if schema:
        record['_schema_shape'] = schema_skeleton(schema)
    msg = data.get('message') or data.get('prompt') or ''
    if isinstance(msg, str):
        record['message_length'] = len(msg)
        # Capture only the first 200 chars so we can spot credential-style
        # phrasing ("enter your API key") without leaking long context.
        record['message_preview'] = msg[:200]

# On ElicitationResult: we record SHAPE of the response, never values.
# Field names are kept because they tell us what was asked; values are not.
if event == 'ElicitationResult':
    result = data.get('result') or data.get('response') or {}
    if isinstance(result, dict):
        record['_response_keys'] = sorted(result.keys())
        record['_response_value_types'] = {k: type(v).__name__ for k, v in result.items()}
    record['accepted'] = bool(data.get('accepted', data.get('confirmed', None)))

print(json.dumps(record))
PYEOF
)
[ -z "$CAPPED" ] && exit 0
printf '%s\n' "$CAPPED" >> "$LOG_FILE" 2>/dev/null || true

echo "[Supercharger] elicitation-discovery: ${1:-payload} logged to $LOG_FILE" >&2
exit 0
