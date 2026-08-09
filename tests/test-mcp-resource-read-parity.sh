#!/usr/bin/env bash
# env-file-guard reaches MCP resource reads; cron-discovery reaches ScheduleWakeup (v2.26.78)
#
# Both are matcher-mode bugs of the same shape, found by the coverage diff on 2026-08-09.
#
# CC matchers have two MODES: a value made only of [A-Za-z0-9_,| -] is split on , or |
# and each token must match EXACTLY; one regex metachar anywhere flips the whole value to
# an unanchored re.search. env-file-guard's matcher was the bare string `Read` — exact
# mode — so ReadMcpResourceTool and ReadMcpResourceDirTool never reached it, and reading
# a .env through an MCP resource server bypassed the guard that exists to stop exactly
# that. The PostToolUse scanners DID see those tools, but only because a sibling `mcp__.*`
# token flipped their matchers into regex mode, where the short `Read` arm matches as a
# substring. Coverage by accident on one event, absent on the other.
#
# Widening the matcher alone would have fixed nothing: the MCP tools' schema is
# {server, uri} with no file_path at all (confirmed against the tool definition).
#
# ScheduleWakeup is the cheaper half — the same "run again later" capability as Cron*,
# unobserved by the discovery hook that exists to learn those payload shapes.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/env-file-guard.sh"

# The matcher-semantics model the suite already trusts (test-mcp-matchers.sh).
CC_MATCH_PY="
import re
SIMPLE=re.compile(r'^[A-Za-z0-9_,| -]*\$')
def cc_matches(matcher, tool):
    if matcher in ('','*'): return True
    if SIMPLE.match(matcher):
        toks=[t.strip() for t in re.split(r'[,|]', matcher) if t.strip()]
        return tool in toks
    try:
        return re.search(matcher, tool) is not None
    except re.error:
        return False
"

read_uri() { # tool uri -> blocked | allowed
  local rc
  TOOL="$1" URI="$2" python3 -c '
import json, os
print(json.dumps({"tool_name":os.environ["TOOL"],
                  "tool_input":{"server":"fs","uri":os.environ["URI"]}}))' \
    | bash "$HOOK" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && echo blocked || echo allowed
}

echo "=== MCP Resource-Read Parity Tests ==="

# --- the guard now inspects the uri field ---
begin_test "a .env read via ReadMcpResourceTool is blocked"
[ "$(read_uri ReadMcpResourceTool 'file:///home/u/project/.env')" = "blocked" ] \
  && pass || fail "MCP resource read bypassed env-file-guard"

begin_test "a .env read via ReadMcpResourceDirTool is blocked"
[ "$(read_uri ReadMcpResourceDirTool 'file:///home/u/project/.env')" = "blocked" ] \
  && pass || fail "the dir-listing sibling was left behind"

begin_test "an SSH private key via uri is blocked"
[ "$(read_uri ReadMcpResourceTool 'file:///home/u/.ssh/id_rsa')" = "blocked" ] \
  && pass || fail "key material readable over MCP"

begin_test "/proc/self/environ via uri is blocked"
[ "$(read_uri ReadMcpResourceTool 'file:///proc/self/environ')" = "blocked" ] \
  && pass || fail "process env readable over MCP"

begin_test "a uri without the file:// scheme still resolves"
[ "$(read_uri ReadMcpResourceTool '/home/u/project/.env')" = "blocked" ] \
  && pass || fail "scheme-less uri missed"

begin_test "a non-file scheme naming .env is still blocked"
[ "$(read_uri ReadMcpResourceTool 'resource://server/config/.env')" = "blocked" ] \
  && pass || fail "only file:// was covered"

# --- and does not over-block ---
begin_test "an ordinary resource read is not blocked"
[ "$(read_uri ReadMcpResourceTool 'file:///home/u/project/README.md')" = "allowed" ] \
  && pass || fail "false positive on a normal resource"

begin_test ".env.example over MCP is still allowed (template)"
[ "$(read_uri ReadMcpResourceTool 'file:///home/u/project/.env.example')" = "allowed" ] \
  && pass || fail "templates must stay readable"

begin_test "the plain Read channel is unchanged"
GOT=$(python3 -c '
import json
print(json.dumps({"tool_name":"Read","tool_input":{"file_path":"/home/u/p/.env"}}))' \
  | bash "$HOOK" >/dev/null 2>&1; echo $?)
[ "$GOT" = "2" ] && pass || fail "regression on the original channel"

begin_test "a Read of an ordinary file is still allowed"
GOT=$(python3 -c '
import json
print(json.dumps({"tool_name":"Read","tool_input":{"file_path":"/home/u/p/main.py"}}))' \
  | bash "$HOOK" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "regression on the original channel"

# --- the registration must actually select those tools ---
begin_test "the env-file-guard matcher selects all three read tools"
RES=$(python3 -c "
$CC_MATCH_PY
import re
src=open('$REPO_DIR/lib/hooks.sh').read()
m=re.search(r'PreToolUse\|([^|]*)\|\\\$\{hooks_dir\}/env-file-guard\.sh', src)
matcher=m.group(1) if m else ''
bad=[t for t in ('Read','ReadMcpResourceTool','ReadMcpResourceDirTool')
     if not cc_matches(matcher,t)]
print('MISSING: '+','.join(bad) if bad else 'OK')")
[ "$RES" = "OK" ] && pass || fail "$RES"

begin_test "cron-discovery's matcher selects ScheduleWakeup"
RES=$(python3 -c "
$CC_MATCH_PY
import re
src=open('$REPO_DIR/lib/hooks.sh').read()
m=re.search(r'PreToolUse\|([^|]*)\|\\\$\{hooks_dir\}/cron-discovery\.sh', src)
matcher=m.group(1) if m else ''
bad=[t for t in ('CronCreate','CronDelete','CronList','ScheduleWakeup')
     if not cc_matches(matcher,t)]
print('MISSING: '+','.join(bad) if bad else 'OK')")
[ "$RES" = "OK" ] && pass || fail "$RES"

begin_test "cron-discovery stays observation-only (never blocks)"
GOT=$(python3 -c '
import json
print(json.dumps({"tool_name":"ScheduleWakeup",
                  "tool_input":{"delaySeconds":600,"prompt":"x","reason":"y"}}))' \
  | SUPERCHARGER_STATE="$(mktemp -d)" bash "$REPO_DIR/hooks/cron-discovery.sh" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "a discovery hook must never block (got rc=$GOT)"

report
