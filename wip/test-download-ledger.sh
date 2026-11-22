#!/usr/bin/env bash
# 2026-11-22: a download in one Bash call, then chmod/run of that file in a LATER call.
# safety-detect.py records each file a download writes in a per-session ledger; a later
# command that makes a recorded file executable or runs it gets an ASK (user decision:
# ask, not deny; reading the file in between does not clear it).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ST=$(mktemp -d); mkdir -p "$ST/scope" "$ST/home" "$ST/w"
trap 'rm -rf "$ST"' EXIT

# probe <session> <command> -> deny | ask | allow
probe() {
  local out rc
  out=$(SID="$1" CMD="$2" W="$ST/w" python3 -c '
import json, os
print(json.dumps({"session_id": os.environ["SID"], "tool_name": "Bash",
                  "tool_input": {"command": os.environ["CMD"]}, "cwd": os.environ["W"]}))' \
    | env HOME="$ST/home" SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/safety.sh" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 2 ]; then printf deny
  elif printf '%s' "$out" | grep -q '"permissionDecision" *: *"ask"'; then printf ask
  elif printf '%s' "$out" | grep -q '"permissionDecision" *: *"deny"'; then printf deny
  else printf allow; fi
}
expect() { # label, want, session, command
  local got; got=$(probe "$3" "$4")
  [ "$got" = "$2" ] && pass || fail "$1: expected $2, got $got"
}

echo "=== download ledger: download, then chmod/run in a later call ==="

begin_test "a plain download is still allowed"
expect "dl" allow s1 'curl -fsSLo /tmp/h https://x.invalid/helper'
begin_test "chmod +x of that file in a later call asks"
expect "chmod" ask s1 'chmod +x /tmp/h'
begin_test "running it in a later call asks"
expect "run" ask s1 '/tmp/h --bg'
begin_test "running it through an interpreter asks"
expect "bash-run" ask s1 'bash /tmp/h'
begin_test "another spelling of the same path asks"
expect "spelling" ask s1 'chmod 755 /tmp/../tmp/h'
begin_test "chmod that removes execute stays allowed"
expect "a-x" allow s1 'chmod a-x /tmp/h'
begin_test "another session is not affected"
expect "other-sid" allow s2 'chmod +x /tmp/h'

begin_test "-O saves under the URL name, relative to the cwd; ./name asks later"
expect "dl-O" allow s3 'curl -fsSLO https://x.invalid/tool.bin'
expect "run-O" ask s3 './tool.bin'
begin_test "wget saves under the URL name; chmod later asks"
expect "wget" allow s4 'wget https://x.invalid/agent'
expect "wget-chmod" ask s4 'chmod u+x agent'

begin_test "same-command download and run is still a deny"
expect "same" deny s5 'curl -fsSLo /tmp/q https://x.invalid/q && chmod +x /tmp/q'

begin_test "no download this session: chmod +x of a script is allowed"
expect "plain" allow s6 'chmod +x scripts/build.sh'

begin_test "no download this session: chmod does not start python"
mkdir -p "$ST/shim"; RP=$(command -v python3)
printf '#!/bin/sh\necho x >> "%s/forks"\nexec "%s" "$@"\n' "$ST" "$RP" > "$ST/shim/python3"; chmod +x "$ST/shim/python3"
: > "$ST/forks"
printf '{"session_id":"s7","tool_name":"Bash","tool_input":{"command":"chmod +x scripts/build.sh"},"cwd":"%s"}' "$ST/w" \
  | env PATH="$ST/shim:$PATH" HOME="$ST/home" SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
[ ! -s "$ST/forks" ] && pass || fail "python3 started $(wc -l < "$ST/forks") time(s) with no download recorded"

report
