#!/usr/bin/env bash
# Suite for /sc-readonly — time-boxed read-only mode.
#   tools/readonly.sh        (writer: on/off/status/cap/scope)
#   hooks/readonly-guard.sh  (PreToolUse enforcer: block edits + mutating bash)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/readonly.sh"
GUARD="$REPO_DIR/hooks/readonly-guard.sh"
CMD="$REPO_DIR/configs/commands/sc-readonly.md"

new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }
# run the guard against a tool-input JSON in state dir $1; echo exit code
guard_rc() { SUPERCHARGER_STATE="$1" bash "$GUARD" <<<"$2" >/dev/null 2>&1; echo $?; }
bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"/tmp","session_id":"sX"}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"; }

# ---- writer ----
begin_test "readonly: <duration> writes a per-session flag by default"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sX bash "$TOOL" 30m >/dev/null 2>&1
[ -f "$D/scope/.readonly-until-sX" ] && [ ! -f "$D/scope/.readonly-until" ] && pass || fail "no per-session flag"
rm -rf "$D"

begin_test "readonly: global scope writes the global flag"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 30m global >/dev/null 2>&1
[ -f "$D/scope/.readonly-until" ] && pass || fail "no global flag"
rm -rf "$D"

begin_test "readonly: caps at 2h"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 9h global >/dev/null 2>&1
DELTA=$(( $(cat "$D/scope/.readonly-until") - $(date +%s) ))
[ "$DELTA" -le 7205 ] && [ "$DELTA" -ge 7100 ] && pass || fail "not capped (delta=$DELTA)"
rm -rf "$D"

begin_test "readonly: off clears both flags"
D=$(new_state)
echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until"
echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until-sX"
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sX bash "$TOOL" off >/dev/null 2>&1
[ ! -f "$D/scope/.readonly-until" ] && [ ! -f "$D/scope/.readonly-until-sX" ] && pass || fail "off left a flag"
rm -rf "$D"

begin_test "readonly: invalid duration exits non-zero"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" banana >/dev/null 2>&1
[ "$?" -ne 0 ] && pass || fail "invalid not rejected"
rm -rf "$D"

# ---- guard: fast-path ----
begin_test "readonly: guard is a no-op when no window is set"
D=$(new_state)
[ "$(guard_rc "$D" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"},"session_id":"sX"}')" -eq 0 ] && pass || fail "blocked with no window"
rm -rf "$D"

# ---- guard: editor tools blocked ----
for T in Write Edit MultiEdit NotebookEdit; do
  begin_test "readonly: blocks $T during the window"
  D=$(new_state); echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until-sX"
  [ "$(guard_rc "$D" '{"tool_name":"'"$T"'","tool_input":{"file_path":"/tmp/x","content":"y"},"session_id":"sX"}')" -eq 2 ] && pass || fail "$T not blocked"
  rm -rf "$D"
done

# ---- guard: bash classifier ----
begin_test "readonly: allows read-only bash (cat/grep/git log/npm test)"
D=$(new_state); echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until-sX"
ok=1
for c in 'cat f 2>/dev/null' 'grep -r x src/' 'git log --oneline' 'npm test' 'ls -la'; do
  [ "$(guard_rc "$D" "$(bash_json "$c")")" -eq 0 ] || { ok=0; echo "  wrongly blocked: $c"; }
done
[ "$ok" -eq 1 ] && pass || fail "read-only command blocked"
rm -rf "$D"

begin_test "readonly: blocks mutating bash (rm/git commit/npm install/sed -i/redirect)"
D=$(new_state); echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until-sX"
ok=1
for c in 'rm -rf /tmp/x' 'git commit -m x' 'npm install left-pad' 'sed -i s/a/b/ f' 'echo hi > out.txt' 'pip install requests'; do
  [ "$(guard_rc "$D" "$(bash_json "$c")")" -eq 2 ] || { ok=0; echo "  wrongly allowed: $c"; }
done
[ "$ok" -eq 1 ] && pass || fail "mutating command allowed"
rm -rf "$D"

# ---- guard: per-session isolation ----
begin_test "readonly: window does NOT apply to a different session"
D=$(new_state); echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until-sX"
[ "$(guard_rc "$D" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"},"session_id":"sOTHER"}')" -eq 0 ] && pass || fail "leaked to another session"
rm -rf "$D"

# ---- precedence: tighten beats loosen ----
begin_test "readonly: blocks a write even when autopilot is also active (tighten > loosen)"
D=$(new_state)
echo $(( $(date +%s)+600 )) > "$D/scope/.readonly-until-sX"
echo $(( $(date +%s)+600 )) > "$D/scope/.autopilot-until-sX"
[ "$(guard_rc "$D" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"},"session_id":"sX"}')" -eq 2 ] && pass || fail "autopilot leaked past read-only"
rm -rf "$D"

# ---- command wiring ----
begin_test "readonly: /sc-readonly command exists and invokes readonly.sh"
[ -f "$CMD" ] && grep -q 'tools/readonly.sh' "$CMD" && pass || fail "command missing or not wired"

# v2.24.4: `status` answers a query, not a predicate — it must exit 0 in both states.
# A trailing `[ -z "$any" ] && echo …` made it return 1 whenever a window was ON.
begin_test "readonly: status exits 0 whether ON or OFF"
_SR=$(mktemp -d); mkdir -p "$_SR/scope"
CLAUDE_PLUGIN_DATA="$_SR" bash "$TOOL" status >/dev/null 2>&1; _off=$?
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$_SR" bash "$TOOL" 30m global >/dev/null 2>&1
CLAUDE_PLUGIN_DATA="$_SR" bash "$TOOL" status >/dev/null 2>&1; _on=$?
rm -rf "$_SR"
{ [ "$_off" = 0 ] && [ "$_on" = 0 ]; } && pass || fail "status rc OFF=$_off ON=$_on (both must be 0)"

report
