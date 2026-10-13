#!/usr/bin/env bash
# output-secrets-scanner is asyncRewake: on a hit it exits 2 and its STDERR is the
# only thing Claude Code delivers, wrapped as
#   Stop hook blocking error from command "PostToolUse:Bash": <stderr>
# For months that stderr was one fixed line naming no tool, no command, no
# pattern and no source, so a FAKE fixture key printed by a background subagent's
# test run read, in the parent, like the parent's own blocking error (8x in one
# session, 2026-10-12/13). These tests pin the attribution: tool, redacted command
# prefix, pattern label, subagent source, and never the secret itself.
# Fake secrets are assembled from parts so this file never holds a whole one.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SCANNER="$REPO_DIR/hooks/output-secrets-scanner.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home"

AKIA="AKIA""IOSFODNN7EXAMPLE"
PGURL="postgres""://user:pass@db.host/app"

# payload <file> <tool> <command> <stdout> [agent_id] [agent_type]
payload() {
  python3 - "$@" <<'PY'
import json, sys
f, tool, cmd, out = sys.argv[1:5]
d = {'session_id': 'attr-sid', 'cwd': '/tmp', 'tool_name': tool,
     'tool_input': {'command': cmd}, 'tool_response': {'stdout': out}}
if len(sys.argv) > 5:
    d['agent_id'] = sys.argv[5]
    d['agent_type'] = sys.argv[6]
open(f, 'w').write(json.dumps(d))
PY
}
run() { HOME="$T/home" bash "$SCANNER" < "$1" 2>"$T/err" >/dev/null; RC=$?; ERR=$(cat "$T/err"); }

begin_test "attribution: names tool, redacted command prefix and pattern type"
payload "$T/p1" Bash "echo $PGURL && npm test --silent" "conn=$PGURL"
run "$T/p1"
case "$ERR" in
  *Bash*'echo postgres[REDACTED]db.host'*'URL with embedded credentials'*) pass ;;
  *) fail "rc=$RC err=$ERR" ;;
esac

begin_test "attribution: never echoes the secret (command or output)"
case "$ERR" in *"user:pass"*|*"$AKIA"*) fail "secret leaked: $ERR" ;; *) pass ;; esac

begin_test "attribution: long command is cut to a short prefix"
payload "$T/p2" Bash "cat fixtures/keys.txt $(printf 'x%.0s' $(seq 1 300))" "id=$AKIA"
run "$T/p2"
case "$ERR" in
  *'cat fixtures/keys.txt'*'AWS access key ID'*) [ "${#ERR}" -lt 700 ] && pass || fail "not truncated: ${#ERR}" ;;
  *) fail "rc=$RC err=$ERR" ;;
esac

begin_test "attribution: subagent-sourced alert is labelled as from a subagent"
payload "$T/p3" Bash "bash tests/run.sh" "key=$AKIA" "a123" "general-purpose"
run "$T/p3"
case "$ERR" in *'from a subagent'*'general-purpose'*) pass ;; *) fail "rc=$RC err=$ERR" ;; esac

begin_test "attribution: parent alert is NOT labelled as a subagent's"
run "$T/p2"
case "$ERR" in *subagent*) fail "parent mislabelled: $ERR" ;; *) pass ;; esac

begin_test "attribution: says it is a warning, nothing was blocked"
case "$ERR" in *'nothing was blocked'*) pass ;; *) fail "err=$ERR" ;; esac

begin_test "detection unchanged: real-shaped secret still exits 2 (parent and subagent)"
run "$T/p2"; R1=$RC; run "$T/p3"; R2=$RC
[ "$R1" -eq 2 ] && [ "$R2" -eq 2 ] && pass || fail "rc parent=$R1 sub=$R2"

begin_test "detection unchanged: clean output stays silent"
payload "$T/p4" Bash "ls" "README.md src tests"
run "$T/p4"
[ "$RC" -eq 0 ] && [ -z "$ERR" ] && pass || fail "rc=$RC err=$ERR"

begin_test "attribution: Read names the file path, MCP names the tool"
python3 -c "import json,sys; open(sys.argv[1],'w').write(json.dumps({'tool_name':'Read','tool_input':{'file_path':'/srv/app/.env.example'},'tool_response':{'output':'K='+sys.argv[2]},'cwd':'/tmp'}))" "$T/p5" "$AKIA"
run "$T/p5"; E1=$ERR
python3 -c "import json,sys; open(sys.argv[1],'w').write(json.dumps({'tool_name':'mcp__db__query','tool_input':{'sql':'select 1'},'tool_response':{'content':[{'type':'text','text':sys.argv[2]}]},'cwd':'/tmp'}))" "$T/p6" "$PGURL"
run "$T/p6"; E2=$ERR
case "$E1|$E2" in
  *'Read'*'/srv/app/.env.example'*'|'*'mcp__db__query'*) pass ;;
  *) fail "read=$E1 mcp=$E2" ;;
esac

report
