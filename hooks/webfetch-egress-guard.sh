#!/usr/bin/env bash
# Claude Supercharger — WebFetch Egress Guard
# Event: PreToolUse | Matcher: WebFetch,WebSearch
# The native WebFetch tool is an un-guarded network-egress channel: an indirect
# prompt-injection can steer the agent into `WebFetch http://169.254.169.254/…`
# (cloud instance-metadata credential theft) or `WebFetch http://10.0.0.5/admin`
# (SSRF into an internal service). safety.sh:288 blocks these on the BASH channel
# and mcp-egress-guard.sh blocks them on the MCP argument channel — this closes
# the parity gap on the WebFetch/WebSearch tool channel. Same block/warn classes
# as mcp-egress-guard (cross-channel parity by design). Fail-open.
# Disable: SUPERCHARGER_WEBFETCH_EGRESS=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_WEBFETCH_EGRESS:-1}" = "0" ] && exit 0

_INPUT=$(cat)

OUT=$(printf '%s\n' "$_INPUT" | PYTHONUTF8=1 python3 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = str(d.get('tool_name') or '')
if tool not in ('WebFetch', 'WebSearch'):
    sys.exit(0)

# Flatten all string values in tool_input (url/prompt/query) into one blob.
parts = []
def walk(x):
    if isinstance(x, str):
        parts.append(x)
    elif isinstance(x, dict):
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
walk(d.get('tool_input'))
blob = ' '.join(parts)
if not blob:
    sys.exit(0)
low = blob.lower()

# BLOCK classes — first match wins (mirrors mcp-egress-guard).
if re.search(r'169\.254\.169\.254|metadata\.google\.internal|169\.254\.170\.2|/latest/meta-data/|computemetadata/v1|/metadata/instance', low):
    reason = 'This WebFetch targets a cloud instance-metadata endpoint (e.g. 169.254.169.254) — a credential-theft SSRF vector. Blocked.'
    block = True
elif re.search(r'discord(app)?\.com/api/webhooks|hooks\.slack\.com/services|outlook\.office\.com/webhook|webhook\.office\.com|discord\.com/api/webhooks', low):
    reason = 'This WebFetch posts to a chat webhook (Discord/Slack/Teams) — a data-exfiltration channel. Blocked.'
    block = True
elif re.search(r'\b(pastebin\.com|paste\.rs|hastebin\.com|dpaste\.|ix\.io|0x0\.st|transfer\.sh|file\.io|termbin\.com|gofile\.io|anonfiles)', low):
    reason = 'This WebFetch targets a paste / anonymous-transfer site (pastebin/transfer.sh/…) — a common exfiltration endpoint. Blocked.'
    block = True
else:
    block = False
    reason = ''

if block:
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': reason,
    }}))
    print('DENY', file=sys.stderr)
    sys.exit(0)

# WARN class — private-network / loopback (SSRF into internal services). Advisory.
if re.search(r'https?://(127\.\d+\.\d+\.\d+|localhost|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2[0-9]|3[01])\.\d+\.\d+|\[::1\]|0\.0\.0\.0)', low):
    msg = '[WEBFETCH-EGRESS] This WebFetch targets a private-network / loopback address — verify it is not an SSRF into an internal service.'
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': msg}}))
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
# A deny envelope must exit 2 so CC blocks the tool (matches every other guard).
printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"' && exit 2
exit 0
