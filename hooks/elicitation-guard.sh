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
# Disable: SUPERCHARGER_ELICITATION_GUARD=0

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

[ "${SUPERCHARGER_ELICITATION_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
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
# v2.7.52: message-text phishing. A server can use an innocuous field name ("value")
# but ask for a credential in prose ("paste your GitHub token here"). Require an
# action verb within a short span of a possessive + credential noun so benign
# prompts ("enter the API endpoint", "type your name") don't trip.
MSG_CRED = re.compile(
    r'(?i)(?:enter|paste|provide|input|type|share|supply|give|copy)\b[^.\n]{0,40}?'
    r'\b(?:your|the|a|an|my)\b[^.\n]{0,25}?'
    r'(?:password|passphrase|api[\s_-]?key|secret[\s_-]?key|secret|token|'
    r'credential|access[\s_-]?key|private[\s_-]?key|personal[\s-]access[\s-]token|'
    r'\bpat\b|client[\s_-]?secret|(?:2fa|otp|one[\s-]?time)[\s-]?code)')

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

# v2.22.8+: also scan the string VALUES of description/title (and examples) — a
# server can use a benign field NAME ("value") and put the credential ask in the
# field's description ("Paste your production database password here"), which
# collect_keys/SCHEMA_META skipped, so neither cred_fields nor the top-level
# message caught it.
def collect_desc_text(o, acc):
    if isinstance(o, dict):
        for k, v in o.items():
            if str(k).lower() in ('description', 'title', 'examples') and isinstance(v, str):
                acc.append(v)
            collect_desc_text(v, acc)
    elif isinstance(o, list):
        for x in o:
            collect_desc_text(x, acc)

_desc_texts = []
collect_desc_text(schema, _desc_texts)

# Message-text phishing signal (independent of field names), incl. schema descriptions.
msg_trigger = bool(MSG_CRED.search(message)) or any(MSG_CRED.search(t) for t in _desc_texts)

# Trusted-server allowlist. Two sources, unioned:
#   1. .supercharger.json trustedElicitationServers (project-level, versioned)
#   2. the global scope allowlist managed by /trust-mcp (scope/.trusted-
#      elicitation-servers) — because .supercharger.json is itself protected by
#      the self-modification path-guard, so the command can't edit it directly.
# v2.7.74: normalize IDENTICALLY to the writer (tools/trust-mcp.sh does
# `tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_.-'`). The reader previously only
# did .strip().lower(), so a server name containing a char the writer strips
# (space, ':', '@') was stored reduced but compared un-reduced → trust silently
# never matched. Mirror the writer so a trusted name always matches.
_ALLOWED = set('abcdefghijklmnopqrstuvwxyz0123456789_.-')
def _normkey(s):
    return ''.join(c for c in str(s).strip().lower() if c in _ALLOWED)

trusted = set()
try:
    with open(os.path.join(os.environ.get('CONFIG_ROOT', ''), '.supercharger.json')) as f:
        cfg = json.load(f)
    for s in (cfg.get('trustedElicitationServers') or []):
        trusted.add(_normkey(s))
except Exception:
    pass
# v2.26.24: read EVERY scope root, not just $HOME. tools/trust-mcp.sh writes via
# sc_scope_dirs(), which treats an explicitly-set CLAUDE_PLUGIN_DATA as the ONLY root
# (v2.24.3). The reader hardcoded $HOME, so under that layout the tool wrote one file
# and the guard read another — /trust-mcp reported success and the server stayed
# untrusted. Fail-safe in direction (it over-declines) but silent, which is the same
# "declared but not effective" class as the inert matchers.
_trust_roots = []
_pd = os.environ.get('CLAUDE_PLUGIN_DATA') or ''
_st = os.environ.get('SUPERCHARGER_STATE') or ''
for _r in (_st, _pd, os.path.join((os.environ.get('HOME') or os.path.expanduser('~')), '.claude', 'supercharger')):
    if _r and _r not in _trust_roots:
        _trust_roots.append(_r)
for _r in _trust_roots:
    try:
        with open(os.path.join(_r, 'scope', '.trusted-elicitation-servers')) as f:
            for line in f:
                s = _normkey(line)
                if s:
                    trusted.add(s)
    except Exception:
        pass

server_l = _normkey(server)
is_trusted = bool(server_l) and server_l in trusted

def audit(action):
    try:
        d = os.path.join((os.environ.get('HOME') or os.path.expanduser('~')), '.claude', 'supercharger', 'audit')
        os.makedirs(d, exist_ok=True)
        rec = {
            'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
            'server': server, 'action': action,
            'cred_fields': sorted(cred_fields),
            'msg_trigger': msg_trigger,
            'trusted': is_trusted,
            'message_preview': message[:120],
        }
        with open(os.path.join(d, 'elicitation-guard.jsonl'), 'a') as f:
            f.write(json.dumps(rec) + '\n')
    except Exception:
        pass

if (cred_fields or msg_trigger) and not is_trusted:
    audit('declined')
    if cred_fields:
        reason = "credential-style field(s) " + ", ".join(sorted(cred_fields))
    else:
        reason = "credential-request phrasing in the prompt text"
    sys.stderr.write(
        "[Supercharger] elicitation-guard: DECLINED " + reason
        + " from MCP server '" + (server or 'unknown') + "'. "
        + "If this server is trusted, add it to trustedElicitationServers in .supercharger.json.\n"
    )
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'Elicitation', 'action': 'decline'}}))
    sys.exit(0)

# Trusted, or no credential fields → let the form proceed (no output = passthrough).
sys.exit(0)
PYEOF
)

if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  # v2.7.50: Elicitation carries no systemMessage/additionalContext, so the
  # decline is otherwise invisible in-session (the form just disappears). Fire a
  # desktop notification — respecting the user's off-switch — in the BACKGROUND so
  # it never delays the block, with stdout/stderr isolated so it can't pollute the
  # decline JSON CC is reading.
  SUPERCHARGER_DIR="$SUPERCHARGER_STATE"
  if [ ! -f "$SUPERCHARGER_DIR/.no-desktop-notify" ]; then
    SRV=$(printf '%s\n' "$_INPUT" | jq -r '.server_name // .mcp_server // .server // .source // empty' 2>/dev/null || true)
    [ -z "$SRV" ] && SRV="an MCP server"
    (
      # shellcheck source=hooks/notify-helper.sh
      . "$HOOKS_DIR/notify-helper.sh"
      _cooldown_ok "elicitation-guard" 10 \
        && _send_notification "Claude — Blocked credential request" \
             "Declined a credential-style input form from ${SRV}. Add it to trustedElicitationServers if this was expected." \
             "Elicitation guard"
    ) >/dev/null 2>&1 &
  fi
fi
exit 0
