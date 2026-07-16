#!/usr/bin/env bash
# Claude Supercharger — MCP Circuit Breaker (reactive)
# Events: PreToolUse | mcp__   (blocks calls to a server in cooldown)
#         PostToolUse | mcp__  (trips the breaker on rate-limit/unavailable output)
# Stops Claude from burning turns hammering an MCP server that just returned
# 429 / 503 / 401 / 403 / rate-limit / overloaded. On such an output the server's
# breaker trips with an escalating cooldown; PreToolUse then denies further calls
# to THAT server until the cooldown expires. A clean success resets the breaker
# (server recovered). Reactive only — no active health probing. Fully fail-open.
# Disable: SUPERCHARGER_MCP_BREAKER=0    Base cooldown: SUPERCHARGER_MCP_COOLDOWN (default 30s)

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_MCP_BREAKER:-1}" = "0" ] && exit 0

_INPUT=$(cat)
SCOPE_DIR="$SUPERCHARGER_STATE/scope"

OUT=$(printf '%s\n' "$_INPUT" | SCOPE_DIR="$SCOPE_DIR" COOLDOWN="${SUPERCHARGER_MCP_COOLDOWN:-30}" PYTHONUTF8=1 python3 -c "
import sys, json, os, re, time

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = str(d.get('tool_name') or '')
if not tool.startswith('mcp__'):
    sys.exit(0)

# server = the segment between the first and second '__'  (mcp__<server>__<tool>)
parts = tool.split('__')
server = parts[1] if len(parts) >= 2 and parts[1] else ''
if not server:
    sys.exit(0)
server_key = re.sub(r'[^a-zA-Z0-9_.-]', '', server)[:64] or 'unknown'

scope_dir = os.environ['SCOPE_DIR']
try:
    base = int(os.environ.get('COOLDOWN', '30') or 30)
except Exception:
    base = 30
now = int(time.time())
hdir = os.path.join(scope_dir, '.mcp-health')
hfile = os.path.join(hdir, server_key)

# Phase: PostToolUse carries tool_response; PreToolUse does not.
event = d.get('hook_event_name') or ''
resp = d.get('tool_response')
is_post = (event == 'PostToolUse') or (resp is not None)

FAIL_RE = re.compile(
    r'(?<![0-9])(429|503|401|403)(?![0-9])'
    r'|rate[ _-]?limit|too many requests|service unavailable|overloaded'
    r'|ECONNREFUSED|ETIMEDOUT|\\bunavailable\\b', re.IGNORECASE)

if is_post:
    blob = ''
    try:
        blob = resp if isinstance(resp, str) else json.dumps(resp)
    except Exception:
        blob = str(resp)
    # Trip on a strong rate-limit/unavailable signal in the response, or an
    # explicit MCP error envelope carrying one.
    if FAIL_RE.search(blob):
        # escalate cooldown by consecutive trip count (capped)
        count = 0
        try:
            with open(hfile) as f:
                count = int((f.read().strip().split('\t') or ['0'])[0])
        except Exception:
            count = 0
        count += 1
        until = now + base * min(count, 5)
        try:
            os.makedirs(hdir, exist_ok=True)
            tmp = hfile + '.tmp'
            with open(tmp, 'w') as f:
                f.write('%d\t%d' % (count, until))
            os.replace(tmp, hfile)
        except Exception:
            pass
    else:
        # clean success -> breaker resets
        try:
            os.remove(hfile)
        except Exception:
            pass
    sys.exit(0)

# PreToolUse: block if the server is in an active cooldown.
try:
    with open(hfile) as f:
        _c, _, raw = f.read().strip().partition('\t')
    until = int(raw or 0)
    count = int(_c or 0)
except Exception:
    sys.exit(0)

if now < until:
    wait = until - now
    msg = ('[MCP-BREAKER] ' + server + ' recently returned rate-limit/unavailable ('
           + str(count) + ' consecutive). Circuit open for ~' + str(wait) + 's — stop calling '
           + server + '; wait or use a different approach. (SUPERCHARGER_MCP_BREAKER=0 to disable.)')
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': msg,
    }}))
    print(msg, file=sys.stderr)
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
exit 2
