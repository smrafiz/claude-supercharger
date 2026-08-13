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

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
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
# 2.21.15: session-scope the breaker. The escalating cooldown counter is driven
# by ONE session's usage; keyed on the server alone, one session tripping a 429
# denied every OTHER concurrent session's calls to that server (and reset their
# state). Key the health file by (server, session) so each session backs off on
# its own signal.
_sid = re.sub(r'[^a-zA-Z0-9_.-]', '', str(d.get('session_id') or 'default'))[:64] or 'default'
server_key = server_key + '__' + _sid

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

# v2.26.44: the pattern above used to run over the WHOLE response body. For a
# server that returns CONTENT rather than status envelopes — a browser tool,
# a docs fetcher, a file reader — the body is arbitrary page text, so ordinary
# pages tripped the breaker. Measured on realistic payloads:
#   \"currently unavailable in your region\"  -> TRIPPED
#   \"what a 503 means for your integration\" -> TRIPPED
#   \"Errors today: 403\"                     -> TRIPPED
# Each opened a 30s+ escalating cooldown on a healthy server. Reported from the
# field as roughly a dozen cooldowns to complete one browser task, which is worse
# than no breaker: the enforced wait exceeded the server's own backoff.
#
# It is also a denial-of-tool vector — page content is attacker-controlled, so a
# site could embed \"rate limit exceeded\" to make Claude stop using the browser.
#
# So: trip only on a signal the SERVER framed as an error.
#   - an explicit error envelope (isError/is_error true, or an 'error' key)
#     -> match FAIL_RE inside it, as before
#   - otherwise, plain content -> require an UNAMBIGUOUS phrase AND a short body.
#     A real error envelope is small; a page of text is not. Bare status numbers
#     and a lone 'unavailable' are dropped from this path entirely.
STRONG_RE = re.compile(
    r'rate[ _-]?limit(ed|ing)?[ _-]?(exceeded|reached|hit)?'
    r'|too many requests|service unavailable|server overloaded'
    r'|ECONNREFUSED|ETIMEDOUT', re.IGNORECASE)
CONTENT_MAX = 2000

def _failure_signal(resp):
    err_part = None
    if isinstance(resp, dict):
        if resp.get('isError') or resp.get('is_error'):
            err_part = resp
        elif resp.get('error') is not None:
            err_part = resp.get('error')
    if err_part is not None:
        try:
            blob = err_part if isinstance(err_part, str) else json.dumps(err_part)
        except Exception:
            blob = str(err_part)
        return bool(FAIL_RE.search(blob))
    try:
        blob = resp if isinstance(resp, str) else json.dumps(resp)
    except Exception:
        blob = str(resp)
    if len(blob) > CONTENT_MAX:
        return False
    return bool(STRONG_RE.search(blob))

if is_post:
    if _failure_signal(resp):
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
