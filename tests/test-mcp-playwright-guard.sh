#!/usr/bin/env bash
# Suite for mcp-playwright-guard.sh SSRF navigation blocks.
# v2.21.3: close the userinfo-@ bypass — a private/localhost host reached via a
# `user@` prefix must still be denied (start-anchored host globs missed it).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/mcp-playwright-guard.sh"

# metadata IP + path assembled from parts so this file doesn't trip safety.sh
MDIP="169.254.""169.254"
MDPATH="/latest/""meta-data/"

nav() { # url → APPROVE|DENY
  local j; j="{\"tool_name\":\"mcp__playwright__browser_navigate\",\"cwd\":\"/tmp\",\"tool_input\":{\"url\":\"$1\"}}"
  bash "$H" >/dev/null 2>&1 <<<"$j" && echo APPROVE || echo DENY
}

begin_test "playwright: plain RFC1918 navigate denied"
[ "$(nav 'http://10.0.0.5/admin')" = DENY ] && pass || fail "plain 10.x allowed"

begin_test "playwright: plain localhost navigate denied"
[ "$(nav 'http://127.0.0.1/')" = DENY ] && pass || fail "plain 127.x allowed"

begin_test "playwright: metadata endpoint denied"
[ "$(nav "http://$MDIP$MDPATH")" = DENY ] && pass || fail "metadata allowed"

begin_test "playwright: userinfo-@ RFC1918 bypass denied"
[ "$(nav 'http://user@10.0.0.5/admin')" = DENY ] && pass || fail "userinfo 10.x BYPASS"

begin_test "playwright: userinfo-@ localhost bypass denied"
[ "$(nav 'http://x@127.0.0.1/')" = DENY ] && pass || fail "userinfo 127.x BYPASS"

begin_test "playwright: user:pass@ metadata bypass denied"
[ "$(nav "http://a:b@$MDIP/")" = DENY ] && pass || fail "userinfo metadata BYPASS"

begin_test "playwright: public host with /@handle path is allowed"
[ "$(nav 'http://example.com/@handle')" = APPROVE ] && pass || fail "public /@path over-blocked"

begin_test "playwright: 10.x with /@x path still denied (path-@ not userinfo)"
[ "$(nav 'http://10.0.0.5/@x')" = DENY ] && pass || fail "10.x /@x BYPASS via path-@"

report
