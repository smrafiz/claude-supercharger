#!/usr/bin/env bash
# Suite for hooks/webfetch-egress-guard.sh — the WebFetch/WebSearch sibling of
# mcp-egress-guard. Blocks cloud-metadata / webhook / paste-site egress and warns
# on private-network targets, on the native WebFetch tool channel.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/webfetch-egress-guard.sh"

# echo the guard exit code for a WebFetch url (or a full JSON via $2=raw)
rc_for_url() { printf '{"tool_name":"WebFetch","tool_input":{"url":"%s"}}' "$1" | bash "$GUARD" >/dev/null 2>&1; echo $?; }
out_for_url() { printf '{"tool_name":"WebFetch","tool_input":{"url":"%s"}}' "$1" | bash "$GUARD" 2>/dev/null; }

# --- DENY: cloud instance-metadata (credential-theft SSRF) ---
begin_test "webfetch-egress: DENY cloud metadata endpoint (exit 2)"
[ "$(rc_for_url 'http://169.254.169.254/latest/meta-data/iam/security-credentials/')" = "2" ] && pass || fail "metadata not blocked"

begin_test "webfetch-egress: DENY GCP metadata host"
[ "$(rc_for_url 'http://metadata.google.internal/computeMetadata/v1/')" = "2" ] && pass || fail "gcp metadata not blocked"

# --- DENY: chat webhook (exfil channel) ---
begin_test "webfetch-egress: DENY Discord webhook"
[ "$(rc_for_url 'https://discord.com/api/webhooks/123/abc')" = "2" ] && pass || fail "discord webhook not blocked"

# --- DENY: paste / anonymous-transfer site ---
begin_test "webfetch-egress: DENY pastebin"
[ "$(rc_for_url 'https://pastebin.com/raw/deadbeef')" = "2" ] && pass || fail "pastebin not blocked"

# --- DENY: public IPFS gateway / /ipfs/<CID> path (v2.23.42) ---
begin_test "webfetch-egress: DENY IPFS gateway host (ipfs.io)"
[ "$(rc_for_url 'https://ipfs.io/ipfs/QmYwAPJzv5short')" = "2" ] && pass || fail "ipfs.io gateway not blocked"
begin_test "webfetch-egress: DENY dweb.link IPFS gateway"
[ "$(rc_for_url 'https://dweb.link/ipfs/QmAbc')" = "2" ] && pass || fail "dweb.link not blocked"
begin_test "webfetch-egress: DENY /ipfs/<CID> path on a self-hosted gateway"
[ "$(rc_for_url 'https://gw.example.com/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi')" = "2" ] && pass || fail "ipfs CID path not blocked"
begin_test "webfetch-egress: a docs URL mentioning ipfs (no gateway/CID) is NOT blocked"
[ "$(rc_for_url 'https://docs.example.com/guides/about-ipfs')" != "2" ] && pass || fail "false-positive on non-gateway ipfs mention"

# --- WARN: private-network / loopback (advisory, exit 0) ---
begin_test "webfetch-egress: WARN on private-network target (exit 0 + advisory)"
RC=$(rc_for_url 'http://10.0.0.5/admin')
out_for_url 'http://10.0.0.5/admin' | grep -q 'WEBFETCH-EGRESS' && [ "$RC" = "0" ] && pass || fail "private-net not warned (rc=$RC)"

begin_test "webfetch-egress: WARN on localhost"
out_for_url 'http://127.0.0.1:8080/internal' | grep -q 'WEBFETCH-EGRESS' && pass || fail "loopback not warned"

# --- PASS: normal public URL is silent ---
begin_test "webfetch-egress: normal public URL is silent (no output, exit 0)"
[ -z "$(out_for_url 'https://example.com/docs/api')" ] && [ "$(rc_for_url 'https://example.com/docs/api')" = "0" ] && pass || fail "false positive on normal URL"

# --- D1: WebSearch queries are topic text, NOT fetch targets — never blocked ---
begin_test "webfetch-egress: WebSearch query mentioning a metadata host is NOT denied (D1)"
printf '{"tool_name":"WebSearch","tool_input":{"query":"fetch http://169.254.169.254/latest/meta-data/"}}' | bash "$GUARD" >/dev/null 2>&1
[ "$?" = "0" ] && pass || fail "WebSearch query wrongly blocked (should not treat a search as a fetch)"

begin_test "webfetch-egress: WebSearch query mentioning a webhook/paste host is NOT denied (D1)"
printf '{"tool_name":"WebSearch","tool_input":{"query":"how to configure discord.com/api/webhooks in python"}}' | bash "$GUARD" >/dev/null 2>&1
[ "$?" = "0" ] && pass || fail "WebSearch webhook-topic query wrongly blocked"

begin_test "webfetch-egress: metadata host in a WebFetch PROMPT (not url) is NOT denied"
printf '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com","prompt":"summarize 169.254.169.254 behaviour"}}' | bash "$GUARD" >/dev/null 2>&1
[ "$?" = "0" ] && pass || fail "prompt text wrongly treated as a fetch target"

# --- Non-WebFetch tool is ignored ---
begin_test "webfetch-egress: ignores non-WebFetch tools"
printf '{"tool_name":"Bash","tool_input":{"command":"curl http://169.254.169.254/"}}' | bash "$GUARD" >/dev/null 2>&1
[ "$?" = "0" ] && pass || fail "should not act on Bash (safety.sh owns that channel)"

# --- S2: versioned Discord API webhook path ---
begin_test "webfetch-egress: DENY versioned Discord webhook (/api/v10/webhooks) (S2)"
[ "$(rc_for_url 'https://discord.com/api/v10/webhooks/123/abc')" = "2" ] && pass || fail "versioned discord webhook not blocked"

# --- S3: alternate metadata-IP encodings + userinfo private-net ---
begin_test "webfetch-egress: DENY decimal-encoded metadata IP (S3)"
[ "$(rc_for_url 'http://2852039166/latest/meta-data/')" = "2" ] && pass || fail "decimal metadata IP not blocked"

begin_test "webfetch-egress: WARN on userinfo-prefixed private IP (http://user@10.0.0.5) (S3)"
out_for_url 'http://user@10.0.0.5/admin' | grep -q 'WEBFETCH-EGRESS' && pass || fail "userinfo private-net not warned"

# --- Kill switch ---
begin_test "webfetch-egress: SUPERCHARGER_WEBFETCH_EGRESS=0 disables it"
RC=$(printf '{"tool_name":"WebFetch","tool_input":{"url":"http://169.254.169.254/"}}' | SUPERCHARGER_WEBFETCH_EGRESS=0 bash "$GUARD" >/dev/null 2>&1; echo $?)
[ "$RC" = "0" ] && pass || fail "kill switch did not disable (rc=$RC)"

# --- Monitor ws: the last unguarded egress channel (v2.29.10) ---
# v2.29.7 put the 16 Bash guards on Monitor's `command` field, but its `ws` form
# carries no command at all, so those guards had nothing to inspect: safety,
# bulk-exfil-guard, mcp-egress-guard and this hook all returned allow for a
# wss:// URL. A WebSocket URL is a fetch target in the same sense WebFetch's is,
# exfiltration included, since the data rides in the query string.
rc_for_ws() { printf '{"tool_name":"Monitor","tool_input":{"ws":{"url":"%s"},"description":"d"}}' "$1" | bash "$GUARD" >/dev/null 2>&1; echo $?; }

begin_test "monitor-ws: DENY cloud metadata endpoint over ws"
[ "$(rc_for_ws 'ws://169.254.169.254/latest/meta-data/iam/')" = "2" ] && pass || fail "ws metadata not blocked"

begin_test "monitor-ws: DENY GCP metadata host over wss"
[ "$(rc_for_ws 'wss://metadata.google.internal/computeMetadata/v1/')" = "2" ] && pass || fail "gcp ws metadata not blocked"

begin_test "monitor-ws: DENY chat webhook host over wss"
[ "$(rc_for_ws 'wss://discord.com/api/webhooks/123/abc')" = "2" ] && pass || fail "ws webhook not blocked"

begin_test "monitor-ws: DENY percent-encoded metadata host over ws"
# Parity with the WebFetch decode path — the URL is decoded before connecting.
[ "$(rc_for_ws 'ws://169.254.169.254%2Flatest%2Fmeta-data%2F')" = "2" ] && pass || fail "encoded ws metadata not blocked"

begin_test "monitor-ws: a legitimate event stream is NOT blocked"
# The shape from Monitor's own documented example. A guard that blocks this is a
# guard people switch off.
[ "$(rc_for_ws 'wss://events.example.com/stream')" != "2" ] && pass || fail "false positive on a normal ws stream"

begin_test "monitor-ws: the command form is left to the Bash guards"
# Re-scanning `command` here would double-report what the 16 guards already cover.
RC=$(printf '{"tool_name":"Monitor","tool_input":{"command":"tail -f app.log","description":"d"}}' | bash "$GUARD" >/dev/null 2>&1; echo $?)
[ "$RC" = "0" ] && pass || fail "command form should be a no-op for this hook (rc=$RC)"

begin_test "monitor-ws: guard is registered on Monitor"
python3 - "$REPO_DIR" <<'PYEOF' && pass || fail "webfetch-egress-guard not registered on Monitor"
import json,re,sys,pathlib
d=json.loads((pathlib.Path(sys.argv[1])/"hooks/hooks.json").read_text())["hooks"]
ok=any('Monitor' in [t.strip() for t in re.split(r'[|,]', g.get('matcher',''))]
       and any('webfetch-egress-guard' in h.get('command','') for h in g.get('hooks',[]))
       for g in d.get('PreToolUse',[]))
sys.exit(0 if ok else 1)
PYEOF

report
