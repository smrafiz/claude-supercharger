#!/usr/bin/env bash
# Claude Supercharger — MCP Egress Guard
# Event: PreToolUse | Matcher: mcp__
# Classifies URLs/hosts in an MCP tool's arguments and blocks the dangerous
# egress classes an MCP server could be steered into hitting: cloud instance-
# metadata (credential theft via SSRF), chat webhooks (discord/slack/teams —
# exfil channels), and paste/transfer sites (pastebin/transfer.sh/…). Private-
# network / loopback targets get a non-blocking warning. Everything else passes.
# Complements the Bash-side safety.sh cloud-metadata block — this is the MCP
# argument channel, which safety.sh never sees. Fail-open.
# Disable: SUPERCHARGER_MCP_EGRESS=0    (from efij Stallion egress_guard.py)

set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_MCP_EGRESS:-1}" = "0" ] && exit 0

_INPUT=$(cat)

OUT=$(printf '%s\n' "$_INPUT" | PYTHONUTF8=1 python3 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = str(d.get('tool_name') or '')
if not tool.startswith('mcp__'):
    sys.exit(0)

# Flatten all string values in tool_input into one blob to scan.
ti = d.get('tool_input')
parts = []
def walk(x):
    if isinstance(x, str):
        parts.append(x)
    elif isinstance(x, dict):
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
walk(ti)
blob = ' '.join(parts)
if not blob:
    sys.exit(0)
low = blob.lower()

# BLOCK classes — first match wins.
# 1. Cloud instance-metadata SSRF (steals instance/IAM creds)
if re.search(r'169\.254\.169\.254|metadata\.google\.internal|169\.254\.170\.2|/latest/meta-data/|computemetadata/v1|/metadata/instance', low):
    reason = 'This MCP call targets a cloud instance-metadata endpoint (e.g. 169.254.169.254) — a credential-theft SSRF vector. Blocked.'
    block = True
# 2. Chat webhooks — common exfiltration channels
elif re.search(r'discord(app)?\.com/api/webhooks|hooks\.slack\.com/services|outlook\.office\.com/webhook|webhook\.office\.com|discord\.com/api/webhooks', low):
    reason = 'This MCP call posts to a chat webhook (Discord/Slack/Teams) — a data-exfiltration channel. Blocked.'
    block = True
# 3. Paste / anonymous-transfer sites
elif re.search(r'\b(pastebin\.com|paste\.rs|hastebin\.com|dpaste\.|ix\.io|0x0\.st|transfer\.sh|file\.io|termbin\.com| ctrl\.v|gofile\.io|anonfiles)', low):
    reason = 'This MCP call targets a paste / anonymous-transfer site (pastebin/transfer.sh/…) — a common exfiltration endpoint. Blocked.'
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
    msg = '[MCP-EGRESS] This MCP call targets a private-network / loopback address — verify it is not an SSRF into an internal service.'
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': msg}}))
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
# A deny envelope must exit 2 so CC blocks the tool (matches every other guard).
printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"' && exit 2
exit 0
