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

# --- Kill switch ---
begin_test "webfetch-egress: SUPERCHARGER_WEBFETCH_EGRESS=0 disables it"
RC=$(printf '{"tool_name":"WebFetch","tool_input":{"url":"http://169.254.169.254/"}}' | SUPERCHARGER_WEBFETCH_EGRESS=0 bash "$GUARD" >/dev/null 2>&1; echo $?)
[ "$RC" = "0" ] && pass || fail "kill switch did not disable (rc=$RC)"

report
