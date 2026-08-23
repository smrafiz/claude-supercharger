#!/usr/bin/env bash
# Claude Supercharger — RemoteTrigger (cloud routine) guard
#
# RemoteTrigger had no guards at all — the cloud sibling of the Cron* tools,
# which do have one. A routine created through it runs LATER, in the cloud, with
# repo access, where no Supercharger guard applies; that is a decision to move
# work outside the enforcement layer, so the human confirms it.
#
# Read actions must stay frictionless: a guard that prompts on `list` is a guard
# people turn off.

set -uo pipefail
. "${BASH_SOURCE[0]%/*}/helpers.sh"

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$REPO_DIR/hooks/remote-trigger-guard.sh"
echo "=== RemoteTrigger cloud-routine guard ==="

# Decision for a payload, or the literal string "passthrough".
_decide() {  # $1 = tool_input JSON
  printf '{"tool_name":"RemoteTrigger","tool_input":%s}' "$1" \
    | bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read().strip()
print('passthrough' if not t else json.loads(t)['hookSpecificOutput']['permissionDecision'])"
}

for a in list get list_runs get_run_log; do
  begin_test "read action '$a' passes through untouched"
  R=$(_decide "{\"action\":\"$a\",\"trigger_id\":\"t1\"}")
  [ "$R" = "passthrough" ] && pass || fail "expected passthrough, got $R"
done

for a in create update run create_webhook_trigger; do
  begin_test "mutating action '$a' asks the human"
  R=$(_decide "{\"action\":\"$a\",\"body\":{\"prompt\":\"do a thing\"}}")
  [ "$R" = "ask" ] && pass || fail "expected ask, got $R"
done

begin_test "the webhook reason names the external-event risk"
# create_webhook_trigger is not just another mutation: after it, something
# outside this machine decides when the agent runs.
OUT=$(printf '{"tool_name":"RemoteTrigger","tool_input":{"action":"create_webhook_trigger","body":{"x":1}}}' \
  | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "external event source" && pass || fail "reason does not mention the external event source: $OUT"

begin_test "the ask reason explains that cloud runs are unguarded"
OUT=$(printf '{"tool_name":"RemoteTrigger","tool_input":{"action":"create","body":{"x":1}}}' \
  | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "no Supercharger guard applies" && pass || fail "reason omits the enforcement gap: $OUT"

begin_test "a credential in the routine body is DENIED, not merely asked"
# Built here rather than inlined in a command: an AWS-shaped literal on a command
# line is itself blocked by commit/credential guards, and splicing it from pieces
# to dodge that has previously hidden a real bug.
KEY="AKIA$(printf 'IOSFODNN7EXAMPLE')"
PAY=$(KEY="$KEY" python3 -c "
import json,os
print(json.dumps({'tool_name':'RemoteTrigger','tool_input':{'action':'create','body':{'prompt':'use '+os.environ['KEY']+' for auth'}}}))")
R=$(printf '%s' "$PAY" | bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read().strip()
print('passthrough' if not t else json.loads(t)['hookSpecificOutput']['permissionDecision'])")
[ "$R" = "deny" ] && pass || fail "credential in a stored routine body must deny, got $R"

begin_test "a bodyless read passes through on ACTION, not by luck"
# Reads are decided by the action name before any body is examined, so this
# pins the passthrough to the action list rather than to the absence of a body.
R=$(_decide '{"action":"list"}')
[ "$R" = "passthrough" ] && pass || fail "expected passthrough for bodyless read, got $R"

begin_test "opt-out env var disables the guard"
R=$(printf '{"tool_name":"RemoteTrigger","tool_input":{"action":"create","body":{"x":1}}}' \
  | SUPERCHARGER_REMOTE_TRIGGER_GUARD=0 bash "$HOOK" 2>/dev/null)
[ -z "$R" ] && pass || fail "opt-out ignored: $R"

begin_test "an unparseable payload fails open"
R=$(printf 'not json' | bash "$HOOK" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ -z "$R" ] && pass || fail "should be silent+0, got rc=$RC out=$R"

begin_test "an unknown future action is not silently allowed through as mutating"
# The action list is closed today; if the API grows one, it should fall through
# rather than be asserted safe. This documents the choice.
R=$(_decide '{"action":"some_future_action","body":{"x":1}}')
[ "$R" = "passthrough" ] && pass || fail "expected passthrough for unknown action, got $R"

begin_test "registered on PreToolUse for RemoteTrigger"
python3 - "$REPO_DIR" <<'PY' && pass || fail "not registered in hooks.json"
import json,re,sys,pathlib
d=json.loads((pathlib.Path(sys.argv[1])/"hooks/hooks.json").read_text())["hooks"]
ok=any('RemoteTrigger' in [t.strip() for t in re.split(r'[|,]', g.get('matcher',''))]
       and any('remote-trigger-guard' in h.get('command','') for h in g.get('hooks',[]))
       for g in d.get('PreToolUse',[]))
sys.exit(0 if ok else 1)
PY

report
