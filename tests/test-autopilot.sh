#!/usr/bin/env bash
# Suite for /sc-autopilot — time-boxed auto-approve.
#   tools/autopilot.sh  (writer: on/off/status/cap/parse)
#   hooks/lib-smart-approve.sh  (reader: approve-all while window active)
# Plus the invariant that the PreToolUse safety floor stays active during autopilot.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/autopilot.sh"
CMD="$REPO_DIR/configs/commands/sc-autopilot.md"

new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }

# ---- writer: tools/autopilot.sh ----
begin_test "autopilot: <duration> writes a future expiry to scope/.autopilot-until"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 30m global >/dev/null 2>&1
UNTIL=$(cat "$D/scope/.autopilot-until" 2>/dev/null || echo 0)
[ "$UNTIL" -gt "$(date +%s)" ] && pass || fail "expiry not in the future"
rm -rf "$D"

begin_test "autopilot: status reports ON while active"
D=$(new_state); echo $(( $(date +%s) + 300 )) > "$D/scope/.autopilot-until"
CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" status 2>&1 | grep -q 'ON' && pass || fail "status did not report ON"
rm -rf "$D"

begin_test "autopilot: off removes the flag and restores prompts"
D=$(new_state); echo $(( $(date +%s) + 300 )) > "$D/scope/.autopilot-until"
CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" off >/dev/null 2>&1
[ ! -f "$D/scope/.autopilot-until" ] && pass || fail "off did not remove the flag"
rm -rf "$D"

begin_test "autopilot: caps duration at the 8h default ceiling"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 9h global >/dev/null 2>&1
UNTIL=$(cat "$D/scope/.autopilot-until"); DELTA=$((UNTIL - $(date +%s)))
[ "$DELTA" -le 28805 ] && [ "$DELTA" -ge 28700 ] && pass || fail "not capped at 8h (delta=$DELTA)"
rm -rf "$D"

begin_test "autopilot: 6h runs the full 6h (under the 8h ceiling, not clamped)"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 6h global >/dev/null 2>&1
DELTA=$(( $(cat "$D/scope/.autopilot-until") - $(date +%s) ))
[ "$DELTA" -le 21605 ] && [ "$DELTA" -ge 21500 ] && pass || fail "6h was clamped (delta=$DELTA, expected ~21600)"
rm -rf "$D"

begin_test "autopilot: SUPERCHARGER_AUTOPILOT_MAX_HOURS raises the ceiling"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID SUPERCHARGER_AUTOPILOT_MAX_HOURS=12 CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 10h global >/dev/null 2>&1
DELTA=$(( $(cat "$D/scope/.autopilot-until") - $(date +%s) ))
[ "$DELTA" -le 36005 ] && [ "$DELTA" -ge 35900 ] && pass || fail "10h not honored under 12h ceiling (delta=$DELTA)"
rm -rf "$D"

begin_test "autopilot: over-ceiling request emits a loud clamp notice"
D=$(new_state)
OUT=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 20h global 2>&1)
printf '%s' "$OUT" | grep -qiE 'exceeds the 8h ceiling|capped at 8h' && pass || fail "no loud clamp notice: $OUT"
rm -rf "$D"

begin_test "autopilot: invalid SUPERCHARGER_AUTOPILOT_MAX_HOURS falls back to 8h"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID SUPERCHARGER_AUTOPILOT_MAX_HOURS=abc CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 20h global >/dev/null 2>&1
DELTA=$(( $(cat "$D/scope/.autopilot-until") - $(date +%s) ))
[ "$DELTA" -le 28805 ] && [ "$DELTA" -ge 28700 ] && pass || fail "invalid ceiling did not fall back to 8h (delta=$DELTA)"
rm -rf "$D"

begin_test "autopilot: bare number is minutes"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 10 global >/dev/null 2>&1
DELTA=$(( $(cat "$D/scope/.autopilot-until") - $(date +%s) ))
[ "$DELTA" -ge 595 ] && [ "$DELTA" -le 605 ] && pass || fail "bare '10' != 10min (delta=$DELTA)"
rm -rf "$D"

begin_test "autopilot: invalid duration exits non-zero and writes nothing"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" banana >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && [ ! -f "$D/scope/.autopilot-until" ] && pass || fail "invalid input not rejected (rc=$RC)"
rm -rf "$D"

# ---- reader: lib-smart-approve verdict ----
DANGER='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/somedir"}}'
verdict() { SUPERCHARGER_STATE="$1" bash -c '. '"$REPO_DIR"'/hooks/lib-smart-approve.sh; smart_approve_verdict "$1" && echo APPROVE || echo DENY' _ "$2"; }

begin_test "autopilot: active window auto-approves a normally-denied call"
D=$(new_state); echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until"
[ "$(verdict "$D" "$DANGER")" = "APPROVE" ] && pass || fail "active window did not approve"
rm -rf "$D"

begin_test "autopilot: expired window falls back to normal (deny)"
D=$(new_state); echo $(( $(date +%s) - 10 )) > "$D/scope/.autopilot-until"
[ "$(verdict "$D" "$DANGER")" = "DENY" ] && pass || fail "expired window still approved"
rm -rf "$D"

begin_test "autopilot: non-numeric flag is ignored (deny)"
D=$(new_state); printf 'notanumber\n' > "$D/scope/.autopilot-until"
[ "$(verdict "$D" "$DANGER")" = "DENY" ] && pass || fail "garbage flag approved"
rm -rf "$D"

# ---- safety floor: PreToolUse guards stay active during autopilot ----
begin_test "autopilot: safety.sh still blocks a protected-path rm during the window"
D=$(new_state); echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until"
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf %s/.ssh"}}' "$HOME" > "$D/rm.json"
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/safety.sh" < "$D/rm.json" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "safety.sh did not block under autopilot"
rm -rf "$D"

begin_test "autopilot: git-safety.sh still blocks force-push during the window"
D=$(new_state); echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until"
printf '{"tool_name":"Bash","tool_input":{"command":"git push --force origin master"}}' > "$D/push.json"
SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/git-safety.sh" < "$D/push.json" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "git-safety.sh did not block under autopilot"
rm -rf "$D"

# ---- per-session scope (default) ----
sess_verdict() { SUPERCHARGER_STATE="$1" bash -c '. '"$REPO_DIR"'/hooks/lib-smart-approve.sh; smart_approve_verdict "$1" && echo APPROVE || echo DENY' _ "$2"; }

begin_test "autopilot: default scope writes a per-session flag (.autopilot-until-<sid>)"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sessA bash "$TOOL" 30m >/dev/null 2>&1
[ -f "$D/scope/.autopilot-until-sessA" ] && [ ! -f "$D/scope/.autopilot-until" ] && pass || fail "did not write a per-session flag"
rm -rf "$D"

begin_test "autopilot: per-session window approves the SAME session"
D=$(new_state); echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until-sessA"
[ "$(sess_verdict "$D" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"session_id":"sessA"}')" = "APPROVE" ] && pass || fail "same session not approved"
rm -rf "$D"

begin_test "autopilot: per-session window does NOT leak to a DIFFERENT session"
D=$(new_state); echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until-sessA"
[ "$(sess_verdict "$D" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"session_id":"sessB"}')" = "DENY" ] && pass || fail "leaked to another session"
rm -rf "$D"

begin_test "autopilot: global scope still approves ANY session"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sessA bash "$TOOL" 30m global >/dev/null 2>&1
[ -f "$D/scope/.autopilot-until" ] && \
[ "$(sess_verdict "$D" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"session_id":"sessZ"}')" = "APPROVE" ] && pass || fail "global did not approve other session"
rm -rf "$D"

begin_test "autopilot: off clears BOTH the per-session and global flags"
D=$(new_state); mkdir -p "$D/scope"
echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until"
echo $(( $(date +%s) + 600 )) > "$D/scope/.autopilot-until-sessA"
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sessA bash "$TOOL" off >/dev/null 2>&1
[ ! -f "$D/scope/.autopilot-until" ] && [ ! -f "$D/scope/.autopilot-until-sessA" ] && pass || fail "off left a flag behind"
rm -rf "$D"

begin_test "autopilot: no session id falls back to a global window"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 30m >/dev/null 2>&1
[ -f "$D/scope/.autopilot-until" ] && pass || fail "no-sid did not fall back to global"
rm -rf "$D"

# ---- command wiring ----
begin_test "autopilot: /sc-autopilot command exists and invokes autopilot.sh"
[ -f "$CMD" ] && grep -q 'tools/autopilot.sh' "$CMD" && pass || fail "command missing or not wired"

# v2.24.4: `status` answers a query — it is not a predicate, so it must exit 0 in both
# states. A trailing `[ -z "$any" ] && echo …` made it return 1 whenever a window was
# ON, so any caller checking $? read a healthy window as a failure.
begin_test "autopilot: status exits 0 whether ON or OFF"
_SR=$(mktemp -d); mkdir -p "$_SR/scope"
CLAUDE_PLUGIN_DATA="$_SR" bash "$TOOL" status >/dev/null 2>&1; _off=$?
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$_SR" bash "$TOOL" 30m global >/dev/null 2>&1
CLAUDE_PLUGIN_DATA="$_SR" bash "$TOOL" status >/dev/null 2>&1; _on=$?
rm -rf "$_SR"
{ [ "$_off" = 0 ] && [ "$_on" = 0 ]; } && pass || fail "status rc OFF=$_off ON=$_on (both must be 0)"

report
