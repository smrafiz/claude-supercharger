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
# shellcheck source=hooks/lib-egress-patterns.sh
. "$HOOKS_DIR/lib-egress-patterns.sh"

[ "${SUPERCHARGER_MCP_EGRESS:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

OUT=$(printf '%s\n' "$_INPUT" | PYTHONUTF8=1 python3 -c "
import os, sys, json, re, urllib.parse

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
# v2.22.5: percent-decode before matching (see webfetch-egress-guard) — 2 rounds.
_dec = blob
for _ in range(2):
    _dec = urllib.parse.unquote(_dec)
low = _dec.lower()

# Shared patterns (lib-egress-patterns.sh, inherited via env) — same source as
# webfetch-egress-guard, so the two can't drift. Empty (lib not sourced) → inert.
META = os.environ.get('EGRESS_METADATA_RE', '')
WEBHOOK = os.environ.get('EGRESS_WEBHOOK_RE', '')
PASTE = os.environ.get('EGRESS_PASTE_RE', '')
IPFS = os.environ.get('EGRESS_IPFS_RE', '')
PRIVATE = os.environ.get('EGRESS_PRIVATE_RE', '')

# BLOCK classes — first match wins.
if META and re.search(META, low):          # cloud instance-metadata SSRF (IAM creds)
    reason = 'This MCP call targets a cloud instance-metadata endpoint (e.g. 169.254.169.254) — a credential-theft SSRF vector. Blocked.'
    block = True
elif WEBHOOK and re.search(WEBHOOK, low):   # chat webhooks — exfil channels
    reason = 'This MCP call posts to a chat webhook (Discord/Slack/Teams) — a data-exfiltration channel. Blocked.'
    block = True
elif PASTE and re.search(PASTE, low):       # paste / anonymous-transfer sites
    reason = 'This MCP call targets a paste / anonymous-transfer site (pastebin/transfer.sh/…) — a common exfiltration endpoint. Blocked.'
    block = True
elif IPFS and re.search(IPFS, low):         # public IPFS gateway / /ipfs/<CID> path
    reason = 'This MCP call targets a public IPFS gateway (ipfs.io/dweb.link/…) or an /ipfs/<CID> path — a content-addressed, anonymous fetch/exfil channel (Miasma-RAT payload class). Blocked.'
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
if PRIVATE and re.search(PRIVATE, low):
    msg = '[MCP-EGRESS] This MCP call targets a private-network / loopback address — verify it is not an SSRF into an internal service.'
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': msg}}))
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
# A deny envelope must exit 2 so CC blocks the tool (matches every other guard).
printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"' && exit 2
exit 0
