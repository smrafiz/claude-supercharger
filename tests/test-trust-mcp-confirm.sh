#!/usr/bin/env bash
# Trusting an MCP server requires a confirm + trust is read from every scope root (v2.26.24)
#
# Completes the loosening audit begun in 2.26.1 (sc-toggle) and continued in 2.26.23
# (hook-toggle). Of the remaining paths, only trust-mcp turned out to loosen security:
#
#   profile-switch minimal  — skips 10 hooks, all advisory/perf; no blocking guard is in
#                             the list, so it is a performance control, not a bypass.
#   autopilot 8h global     — removes permission PROMPTS; every PreToolUse guard still
#                             runs, and it is capped at 8h with a loud clamp.
#   SUPERCHARGER_*=0        — NOT agent-exploitable. A hook runs in Claude Code's process
#                             environment, not the command's, so an env prefix inside a
#                             tool call ("SUPERCHARGER_X=0 cmd") never reaches the guard.
#                             Verified: the prefixed command is still DENIED.
#   trust-mcp <server>      — DOES loosen. Verified: a credential-shaped Elicitation form
#                             from an untrusted server DECLINEs; after trusting, ALLOWs.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HT="$REPO_DIR/hooks/harness-tamper-guard.sh"

decision() {
  local out rc
  out=$(printf '%s' "$(CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | bash "$HT" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo deny
  elif printf '%s' "$out" | grep -q '"ask"'; then echo ask
  else echo allow; fi
}

# Ask elicitation-guard whether a credential form from $1 is permitted, with the trust
# file placed in the scope root named by $2 (env var name) — proves reader/writer agree.
elicit_with_root() { # server, root-dir, env-name
  local srv="$1" root="$2" envname="$3" out
  mkdir -p "$root/scope"
  printf '%s\n' "$srv" > "$root/scope/.trusted-elicitation-servers"
  out=$(python3 -c "
import json, sys
print(json.dumps({'server_name': sys.argv[1],
                  'schema': {'properties': {'api_key': {'type':'string','title':'API Key'}}}}))" "$srv" \
    | env "$envname=$root" bash "$REPO_DIR/hooks/elicitation-guard.sh" 2>/dev/null)
  printf '%s' "$out" | grep -qi 'decline\|deny' && echo DECLINE || echo ALLOW
}

echo "=== trust-mcp Confirm Tests ==="

begin_test "trusting a server raises a confirm"
[ "$(decision 'bash ~/.claude/supercharger/tools/trust-mcp.sh some-server')" = "ask" ] && pass || fail "no confirm"

begin_test "the confirm names the actual risk (credential harvest)"
OUT=$(printf '%s' "$(CMD='bash tools/trust-mcp.sh evil' python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
  | bash "$HT" 2>/dev/null)
printf '%s' "$OUT" | grep -qi 'api keys\|credential' && pass || fail "confirm does not state the risk: $OUT"

begin_test "REMOVING trust is not gated (tightening never prompts)"
[ "$(decision 'bash tools/trust-mcp.sh --remove some-server')" = "allow" ] && pass || fail "removal should not prompt"

begin_test "listing trusted servers is not gated"
[ "$(decision 'bash tools/trust-mcp.sh --list')" = "allow" ] && pass || fail "listing should not prompt"

begin_test "unrelated commands are unaffected"
[ "$(decision 'ls -la')" = "allow" ] && pass || fail "over-matched"

# --- autopilot must not swallow it ---
begin_test "AUTOPILOT cannot auto-approve trusting a server"
ST=$(mktemp -d); mkdir -p "$ST/scope"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$ST/scope/.autopilot-until"
GOT=$(SUPERCHARGER_STATE="$ST" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
inp=$(CMD="bash tools/trust-mcp.sh evil" python3 -c "
import json,os
print(json.dumps({\"tool_name\":\"Bash\",\"tool_input\":{\"command\":os.environ[\"CMD\"]}}))")
if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi')
[ "$GOT" = "no" ] && pass || fail "autopilot auto-approved it (got: $GOT)"
rm -rf "$ST"

# --- the reader/writer path divergence ---
begin_test "trust is honoured when stored under SUPERCHARGER_STATE"
TD=$(mktemp -d)
[ "$(elicit_with_root trusted-srv "$TD" SUPERCHARGER_STATE)" = "ALLOW" ] && pass \
  || fail "trust under SUPERCHARGER_STATE was ignored"
rm -rf "$TD"

begin_test "trust is honoured when stored under CLAUDE_PLUGIN_DATA (plugin layout)"
TD=$(mktemp -d)
[ "$(elicit_with_root trusted-srv "$TD" CLAUDE_PLUGIN_DATA)" = "ALLOW" ] && pass \
  || fail "trust written by the tool under the plugin root was never read — /trust-mcp reports success and does nothing"
rm -rf "$TD"

begin_test "an untrusted server is still declined (the guard still guards)"
TD=$(mktemp -d); mkdir -p "$TD/scope"
printf 'someone-else\n' > "$TD/scope/.trusted-elicitation-servers"
OUT=$(python3 -c "
import json
print(json.dumps({'server_name':'evil','schema':{'properties':{'api_key':{'type':'string'}}}}))" \
  | env SUPERCHARGER_STATE="$TD" bash "$REPO_DIR/hooks/elicitation-guard.sh" 2>/dev/null)
printf '%s' "$OUT" | grep -qi 'decline\|deny' && pass || fail "untrusted server was allowed"
rm -rf "$TD"

report
