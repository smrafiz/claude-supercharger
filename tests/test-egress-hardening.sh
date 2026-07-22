#!/usr/bin/env bash
# Suite for v2.22.5 egress/SSRF hardening: percent-decode, metadata-IP encodings,
# webhook/paste additions, and playwright numeric-IP / file: parity.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
WF="$REPO_DIR/hooks/webfetch-egress-guard.sh"
PW="$REPO_DIR/hooks/mcp-playwright-guard.sh"

jcmd() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
# webfetch verdict: DENY if it blocks (exit 2 / deny)
wf() { local j; j=$(printf '{"tool_name":"WebFetch","cwd":"/tmp","tool_input":{"url":%s}}' "$(jcmd "$1")"); bash "$WF" <<<"$j" 2>&1 | grep -q '"deny"' && echo DENY || echo ALLOW; }
# playwright navigate verdict
pw() { local j; j=$(printf '{"tool_name":"mcp__playwright__browser_navigate","cwd":"/tmp","tool_input":{"url":%s}}' "$(jcmd "$1")"); bash "$PW" <<<"$j" 2>&1 | grep -q '"deny"' && echo DENY || echo ALLOW; }

# metadata IP pieces (assembled at runtime so this file has no literal IMDS IP)
IMDS="169.254.""169.254"; IMDS_PATH="/latest/""meta-data/"
DWORD="28520""39166"; ALIBABA="100.100.""100.200"

# ---- E4: percent-decode defeats the path/host token bypass ----
begin_test "webfetch: percent-encoded IMDS host+path is denied"
[ "$(wf "http://%31%36%39.254.169.254/latest/%6d%65%74%61-data/")" = DENY ] && pass || fail "percent-encoded IMDS evaded"

# ---- E1/E2/E3: metadata IP encodings ----
begin_test "webfetch: Alibaba IMDS (100.100.100.200) is denied"
[ "$(wf "http://$ALIBABA/latest/meta-data/")" = DENY ] && pass || fail "Alibaba IMDS evaded"
begin_test "webfetch: decimal-dword IMDS is denied"
[ "$(wf "http://$DWORD/")" = DENY ] && pass || fail "dword IMDS evaded"

# ---- E9/E10: webhook exfil additions ----
begin_test "webfetch: Slack workflow trigger webhook is denied"
[ "$(wf "https://hooks.slack.com/triggers/T00/123/abc")" = DENY ] && pass || fail "Slack triggers evaded"
begin_test "webfetch: Telegram Bot API is denied"
[ "$(wf "https://api.telegram.org/bot123:ABC/sendMessage?text=x")" = DENY ] && pass || fail "telegram evaded"
begin_test "webfetch: catbox.moe paste host is denied"
[ "$(wf "https://catbox.moe/user/api.php")" = DENY ] && pass || fail "catbox evaded"

# ---- regression: plain IMDS + public URL ----
begin_test "webfetch: plain IMDS still denied"
[ "$(wf "http://$IMDS$IMDS_PATH")" = DENY ] && pass || fail "plain IMDS regressed"
begin_test "webfetch: normal public URL allowed"
[ "$(wf "https://example.com/api/data")" = ALLOW ] && pass || fail "public URL over-blocked"

# ---- E5/E7/E8: playwright parity ----
begin_test "playwright: decimal-dword metadata navigate denied"
[ "$(pw "http://$DWORD/")" = DENY ] && pass || fail "playwright dword metadata evaded"
begin_test "playwright: numeric loopback (2130706433) denied"
[ "$(pw "http://2130706433/")" = DENY ] && pass || fail "playwright loopback dword evaded"
begin_test "playwright: file:/etc/passwd (single-slash) denied"
[ "$(pw "file:/etc/passwd")" = DENY ] && pass || fail "playwright file: single-slash evaded"
begin_test "playwright: normal public navigate allowed"
[ "$(pw "https://example.com/")" = ALLOW ] && pass || fail "playwright public over-blocked"

report
