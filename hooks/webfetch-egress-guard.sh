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
# shellcheck source=hooks/lib-egress-patterns.sh
. "$HOOKS_DIR/lib-egress-patterns.sh"

[ "${SUPERCHARGER_WEBFETCH_EGRESS:-1}" = "0" ] && exit 0

_INPUT=$(cat)

OUT=$(printf '%s\n' "$_INPUT" | PYTHONUTF8=1 python3 -c "
import os, sys, json, re, urllib.parse

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = str(d.get('tool_name') or '')
if tool not in ('WebFetch', 'WebSearch'):
    sys.exit(0)

# Scan the FETCH TARGET only: WebFetch url. A WebSearch query is topic text routed
# through a mediated search, not a URL this tool fetches, so it must never be treated
# as an egress target (else a legit search mentioning a webhook/paste/metadata host is
# wrongly blocked). WebFetch prompt is processing instructions, not a target. WebSearch
# has no fetch target here, so it is a no-op.
ti = d.get('tool_input') or {}
blob = str(ti.get('url') or '') if (tool == 'WebFetch' and isinstance(ti, dict)) else ''
if not blob:
    sys.exit(0)
# v2.22.5: percent-decode before matching. The tool decodes the URL before the
# request, so a percent-encoded host or path defeated every host/path token.
# Two rounds catches double-encoding.
_dec = blob
for _ in range(2):
    _dec = urllib.parse.unquote(_dec)
low = _dec.lower()

# Shared patterns (lib-egress-patterns.sh, inherited via env) — same source as
# mcp-egress-guard, so the two can't drift. Empty (lib not sourced) → inert, not
# match-everything.
META = os.environ.get('EGRESS_METADATA_RE', '')
WEBHOOK = os.environ.get('EGRESS_WEBHOOK_RE', '')
PASTE = os.environ.get('EGRESS_PASTE_RE', '')
IPFS = os.environ.get('EGRESS_IPFS_RE', '')
PRIVATE = os.environ.get('EGRESS_PRIVATE_RE', '')

# BLOCK classes — first match wins (mirrors mcp-egress-guard).
if META and re.search(META, low):
    reason = 'This WebFetch targets a cloud instance-metadata endpoint (e.g. 169.254.169.254) — a credential-theft SSRF vector. Blocked.'
    block = True
elif WEBHOOK and re.search(WEBHOOK, low):
    reason = 'This WebFetch posts to a chat webhook (Discord/Slack/Teams) — a data-exfiltration channel. Blocked.'
    block = True
elif PASTE and re.search(PASTE, low):
    reason = 'This WebFetch targets a paste / anonymous-transfer site (pastebin/transfer.sh/…) — a common exfiltration endpoint. Blocked.'
    block = True
elif IPFS and re.search(IPFS, low):
    reason = 'This WebFetch targets a public IPFS gateway (ipfs.io/dweb.link/…) or an /ipfs/<CID> path — a content-addressed, anonymous fetch/exfil channel (Miasma-RAT payload class). Blocked.'
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
    msg = '[WEBFETCH-EGRESS] This WebFetch targets a private-network / loopback address — verify it is not an SSRF into an internal service.'
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': msg}}))
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
# A deny envelope must exit 2 so CC blocks the tool (matches every other guard).
printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"' && exit 2
exit 0
