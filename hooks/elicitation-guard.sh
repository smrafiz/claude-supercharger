#!/usr/bin/env bash
# Claude Supercharger — Elicitation Guard
# Event: Elicitation | Matcher: * | SYNC (blocking)
#
# MCP servers can solicit structured input from the user via Elicitation forms —
# a legitimate UX primitive, but also a direct credential-harvesting vector: a
# malicious or compromised server can ask for an "API token", "database password",
# or "GitHub PAT" in a form that looks routine. This guard DECLINES an elicitation
# when its requested schema contains credential-style field names AND the server
# is not on the project's trusted list.
#
# The companion elicitation-discovery.sh (async) LOGS every elicitation; this hook
# BLOCKS the dangerous subset. Elicitation cannot carry additionalContext/
# systemMessage, so the block surfaces via the declined form + an audit record +
# stderr (visible with debug hooks on).
#
# Decline shape (per CC hooks contract):
#   {"hookSpecificOutput":{"hookEventName":"Elicitation","action":"decline"}}
#
# Trust a server (allow its credential fields):
#   .supercharger.json → {"trustedElicitationServers": ["postgres", "my-server"]}
# Disable entirely: SUPERCHARGER_ELICITATION_GUARD=0  (or disable "elicitation-guard")
# Audit: ~/.claude/supercharger/audit/elicitation-guard.jsonl

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

[ "${SUPERCHARGER_ELICITATION_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
CONFIG_ROOT=$(_resolve_project_root "$PROJECT_DIR")
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "elicitation-guard" && exit 0

# One python fork: parse payload, extract server + schema field names, match
# credential-style names, consult the trusted allowlist, emit a decline if unsafe.
OUT=$(HOOK_INPUT="$_INPUT" CONFIG_ROOT="$CONFIG_ROOT" python3 <<'PYEOF' 2>/dev/null || true
import json, os, re, sys, datetime

raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    # Unparseable hook payload is our bug, not an attack surface (CC builds it) —
    # fail OPEN so a parser quirk can't break every legitimate elicitation.
    sys.exit(0)

# Defensive key fallbacks — the exact Elicitation payload shape is not pinned in
# the docs, so accept the same alternatives elicitation-discovery.sh handles.
server = (data.get('server_name') or data.get('mcp_server') or data.get('server')
          or data.get('source') or '')
schema = (data.get('schema') or data.get('requestedSchema') or data.get('requested_schema')
          or data.get('elicitation_schema') or {})
message = data.get('message') or data.get('prompt') or ''
if not isinstance(message, str):
    message = ''

# Collect every dict key in the schema (handles JSON-Schema `properties` nesting
# and flat shapes alike). JSON-Schema meta keys are ignored below.
def collect_keys(o, acc):
    if isinstance(o, dict):
        for k, v in o.items():
            acc.add(k)
            collect_keys(v, acc)
    elif isinstance(o, list):
        for x in o:
            collect_keys(x, acc)

keys = set()
collect_keys(schema, keys)

SCHEMA_META = {
    'type', 'properties', 'required', 'description', 'title', 'items', 'enum',
    'default', 'format', 'minimum', 'maximum', 'minlength', 'maxlength', 'pattern',
    'additionalproperties', '$schema', '$id', 'anyof', 'oneof', 'allof', 'const',
    'examples', 'definitions', '$defs', 'nullable', 'readonly', 'writeonly',
}
# Unambiguous credential words: match anywhere in the (normalized) field name.
STRONG = re.compile(r'password|passwd|passphrase|secret|token|credential|'
                    r'api[_-]?key|apikey|bearer|private[_-]?key|access[_-]?key|'
                    r'client[_-]?secret')
# Short/ambiguous words: require a token boundary so "monkey" != key, "patch" != pat.
DELIM = re.compile(r'(?:^|[_\-])(key|pat|pin|otp|mfa|auth|creds?|pwd)(?:$|[_\-])')

def norm(name):
    # split camelCase → snake so apiKey/githubToken normalize before matching
    return re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', str(name)).lower()

cred_fields = []
for k in keys:
    n = norm(k)
    if n in SCHEMA_META:
        continue
    if STRONG.search(n) or DELIM.search(n):
        cred_fields.append(k)

# Trusted-server allowlist from .supercharger.json (project-level opt-in).
trusted = set()
try:
    with open(os.path.join(os.environ.get('CONFIG_ROOT', ''), '.supercharger.json')) as f:
        cfg = json.load(f)
    for s in (cfg.get('trustedElicitationServers') or []):
        trusted.add(str(s).strip().lower())
except Exception:
    pass

server_l = str(server).strip().lower()
is_trusted = bool(server_l) and server_l in trusted

def audit(action):
    try:
        d = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'audit')
        os.makedirs(d, exist_ok=True)
        rec = {
            'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
            'server': server, 'action': action,
            'cred_fields': sorted(cred_fields),
            'trusted': is_trusted,
            'message_preview': message[:120],
        }
        with open(os.path.join(d, 'elicitation-guard.jsonl'), 'a') as f:
            f.write(json.dumps(rec) + '\n')
    except Exception:
        pass

if cred_fields and not is_trusted:
    audit('declined')
    sys.stderr.write(
        "[Supercharger] elicitation-guard: DECLINED credential-style field(s) "
        + ", ".join(sorted(cred_fields))
        + " from MCP server '" + (server or 'unknown') + "'. "
        + "If this server is trusted, add it to trustedElicitationServers in .supercharger.json.\n"
    )
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'Elicitation', 'action': 'decline'}}))
    sys.exit(0)

# Trusted, or no credential fields → let the form proceed (no output = passthrough).
sys.exit(0)
PYEOF
)

[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
