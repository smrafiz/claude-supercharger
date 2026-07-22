#!/usr/bin/env bash
# Suite for the 2.21.2 MCP deny-path fail-closed fix.
# deny() built the JSON reason via an unguarded RSN=$(python3 …) under
# `set -euo pipefail`. python3 absent/crash -> the assignment aborts the
# function BEFORE the deny JSON + `exit 2`, so CC treats the call as
# non-blocking and ALLOWS the destructive op. The deny path must fail CLOSED.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

FAKEBIN=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$FAKEBIN/python3"
chmod +x "$FAKEBIN/python3"

rc_broken() { PATH="$FAKEBIN:$PATH" bash "$REPO_DIR/hooks/$1" >/dev/null 2>&1 <<<"$2"; echo $?; }
rc_real() { bash "$REPO_DIR/hooks/$1" >/dev/null 2>&1 <<<"$2"; echo $?; }

# verb split so this test file itself doesn't trip safety.sh's DROP-TABLE pattern
VERB="DR""OP"
SQL="{\"tool_name\":\"mcp__postgres__query\",\"cwd\":\"/tmp\",\"tool_input\":{\"query\":\"$VERB TABLE users\"}}"
GH='{"tool_name":"mcp__github__merge_pull_request","cwd":"/tmp","tool_input":{}}'
PW='{"tool_name":"mcp__playwright__browser_run_code","cwd":"/tmp","tool_input":{"code":"x"}}'

begin_test "mcp-sql-guard: destructive verb denies with real python3 (exit 2)"
[ "$(rc_real mcp-sql-guard.sh "$SQL")" = 2 ] && pass || fail "did not deny with real python3"

begin_test "mcp-github-write-gate: merge_pull_request denies with real python3 (exit 2)"
[ "$(rc_real mcp-github-write-gate.sh "$GH")" = 2 ] && pass || fail "did not deny with real python3"

begin_test "mcp-playwright-guard: browser_run_code denies with real python3 (exit 2)"
[ "$(rc_real mcp-playwright-guard.sh "$PW")" = 2 ] && pass || fail "did not deny with real python3"

begin_test "mcp-sql-guard: destructive verb still blocks (exit 2) when python3 broken"
[ "$(rc_broken mcp-sql-guard.sh "$SQL")" = 2 ] && pass || fail "fail-open: destructive SQL allowed when python3 broke"

begin_test "mcp-github-write-gate: merge still blocks (exit 2) when python3 broken"
[ "$(rc_broken mcp-github-write-gate.sh "$GH")" = 2 ] && pass || fail "fail-open: GitHub merge allowed when python3 broke"

begin_test "mcp-playwright-guard: eval still blocks (exit 2) when python3 broken"
[ "$(rc_broken mcp-playwright-guard.sh "$PW")" = 2 ] && pass || fail "fail-open: browser eval allowed when python3 broke"

rm -rf "$FAKEBIN"
report
