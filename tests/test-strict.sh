#!/usr/bin/env bash
# Suite for /sc-strict — time-boxed "auto-approve nothing" mode.
#   tools/strict.sh              (writer)
#   hooks/lib-smart-approve.sh   (verdict: strict → never auto-approve; overrides autopilot)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/strict.sh"
CMD="$REPO_DIR/configs/commands/sc-strict.md"

new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }
verdict() { SUPERCHARGER_STATE="$1" bash -c '. '"$REPO_DIR"'/hooks/lib-smart-approve.sh; smart_approve_verdict "$1" && echo APPROVE || echo DENY' _ "$2"; }
# a tool that is normally auto-approved (Read), for session $1
safe_read() { printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"session_id":"%s"}' "$1"; }
future() { echo $(( $(date +%s) + 600 )); }

# ---- writer ----
begin_test "strict: <duration> writes a per-session flag by default"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sX bash "$TOOL" 30m >/dev/null 2>&1
[ -f "$D/scope/.strict-until-sX" ] && [ ! -f "$D/scope/.strict-until" ] && pass || fail "no per-session flag"
rm -rf "$D"

begin_test "strict: global scope writes the global flag"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 30m global >/dev/null 2>&1
[ -f "$D/scope/.strict-until" ] && pass || fail "no global flag"
rm -rf "$D"

begin_test "strict: caps at 2h"
D=$(new_state)
env -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" 9h global >/dev/null 2>&1
DELTA=$(( $(cat "$D/scope/.strict-until") - $(date +%s) ))
[ "$DELTA" -le 7205 ] && [ "$DELTA" -ge 7100 ] && pass || fail "not capped (delta=$DELTA)"
rm -rf "$D"

begin_test "strict: off clears both flags"
D=$(new_state); future > "$D/scope/.strict-until"; future > "$D/scope/.strict-until-sX"
CLAUDE_PLUGIN_DATA="$D" CLAUDE_CODE_SESSION_ID=sX bash "$TOOL" off >/dev/null 2>&1
[ ! -f "$D/scope/.strict-until" ] && [ ! -f "$D/scope/.strict-until-sX" ] && pass || fail "off left a flag"
rm -rf "$D"

begin_test "strict: invalid duration exits non-zero"
D=$(new_state)
CLAUDE_PLUGIN_DATA="$D" bash "$TOOL" banana >/dev/null 2>&1
[ "$?" -ne 0 ] && pass || fail "invalid not rejected"
rm -rf "$D"

# ---- verdict ----
begin_test "strict: OFF — a normally-safe tool is auto-approved"
D=$(new_state)
[ "$(verdict "$D" "$(safe_read sX)")" = "APPROVE" ] && pass || fail "safe tool not approved with strict off"
rm -rf "$D"

begin_test "strict: ON — even a safe tool is NOT auto-approved (falls through to prompt)"
D=$(new_state); future > "$D/scope/.strict-until-sX"
[ "$(verdict "$D" "$(safe_read sX)")" = "DENY" ] && pass || fail "strict did not suppress auto-approve"
rm -rf "$D"

# ---- the family invariant: tighten beats loosen ----
begin_test "strict: OVERRIDES autopilot (both active → auto-approve nothing)"
D=$(new_state); future > "$D/scope/.strict-until-sX"; future > "$D/scope/.autopilot-until-sX"
[ "$(verdict "$D" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"session_id":"sX"}')" = "DENY" ] && pass || fail "autopilot leaked past strict"
rm -rf "$D"

# ---- per-session isolation ----
begin_test "strict: window does NOT apply to a different session"
D=$(new_state); future > "$D/scope/.strict-until-sX"
# sOTHER has no strict flag → its safe tool is still auto-approved
[ "$(verdict "$D" "$(safe_read sOTHER)")" = "APPROVE" ] && pass || fail "strict leaked to another session"
rm -rf "$D"

# ---- command wiring ----
begin_test "strict: /sc-strict command exists and invokes strict.sh"
[ -f "$CMD" ] && grep -q 'tools/strict.sh' "$CMD" && pass || fail "command missing or not wired"

report
