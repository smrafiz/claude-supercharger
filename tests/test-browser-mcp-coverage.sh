#!/usr/bin/env bash
# Suite for v2.22.13 — browser-MCP guard broadened beyond playwright/puppeteer to
# browserbase / browser-use / chrome-devtools / stagehand (different tool names).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/mcp-playwright-guard.sh"

jval() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
# nav <tool> <url> → DENY|ALLOW
nav() { local j; j=$(printf '{"tool_name":"%s","cwd":"/tmp","tool_input":{"url":%s}}' "$1" "$(jval "$2")"); bash "$H" <<<"$j" 2>&1 | grep -q '"deny"' && echo DENY || echo ALLOW; }
# ev <tool> → DENY|ALLOW  (eval tool, no url needed)
ev() { local j; j=$(printf '{"tool_name":"%s","cwd":"/tmp","tool_input":{"code":"x"}}' "$1"); bash "$H" <<<"$j" 2>&1 | grep -q '"deny"' && echo DENY || echo ALLOW; }

IMDS="169.254.""169.254"

begin_test "browser-mcp: browserbase navigate to metadata IP is denied"
[ "$(nav "mcp__browserbase__browserbase_navigate" "http://$IMDS/")" = DENY ] && pass || fail "browserbase navigate not guarded"
begin_test "browser-mcp: stagehand navigate to localhost is denied"
[ "$(nav "mcp__stagehand__stagehand_navigate" "http://127.0.0.1/admin")" = DENY ] && pass || fail "stagehand navigate not guarded"
begin_test "browser-mcp: chrome-devtools navigate to RFC1918 is denied"
[ "$(nav "mcp__chrome-devtools__navigate_page" "http://10.0.0.5/")" = DENY ] && pass || fail "chrome-devtools navigate not guarded"
begin_test "browser-mcp: browser-use eval tool is denied"
[ "$(ev "mcp__browser-use__run_js")" = DENY ] && pass || fail "browser-use eval not guarded"

# ---- regressions ----
begin_test "browser-mcp: playwright navigate still guarded (metadata)"
[ "$(nav "mcp__playwright__browser_navigate" "http://$IMDS/")" = DENY ] && pass || fail "playwright regressed"
begin_test "browser-mcp: benign public navigate allowed"
[ "$(nav "mcp__browserbase__browserbase_navigate" "https://example.com/")" = ALLOW ] && pass || fail "public navigate over-blocked"

begin_test "registration: browser MCPs in matcher (lib + plugin)"
grep -q 'mcp__browserbase__.*mcp-playwright-guard' "$REPO_DIR/lib/hooks.sh" && grep -q 'mcp__stagehand__' "$REPO_DIR/hooks/hooks.json" && pass || fail "matcher missing browser MCPs"

report
