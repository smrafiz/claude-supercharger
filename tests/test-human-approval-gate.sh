#!/usr/bin/env bash
# Suite for human-approval-gate.sh.
# v2.21.4: the pending marker is session-scoped, so session B never rides on
# session A's approval.
# 2026-11-17 (from tsrmehmet/memokit): a retry alone no longer counts as approval.
# The gate names a code, and only the USER's prompt `approve <code>` (seen by the
# same hook on UserPromptSubmit) grants it, once. Claude retrying is not the user.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/human-approval-gate.sh"

# high-risk trigger built from parts so this file doesn't trip safety.sh
RH="reset --""hard"
mkcmd() { printf 'git %s HEAD' "$RH"; }

# run <state_dir> <session_id> → exit code (2 = blocked, 0 = allowed); message in $D/out
run() {
  local j; j="{\"tool_name\":\"Bash\",\"cwd\":\"/tmp\",\"session_id\":\"$2\",\"tool_input\":{\"command\":\"$(mkcmd)\"}}"
  SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_STATE="$1" bash "$H" >"$1/out" 2>&1 <<<"$j"; echo $?
}
# say <state_dir> <session_id> <prompt> → the user's prompt, as UserPromptSubmit sends it
say() {
  P="$3" SID="$2" python3 -c "import json,os;print(json.dumps({'hook_event_name':'UserPromptSubmit','session_id':os.environ['SID'],'cwd':'/tmp','prompt':os.environ['P']}))" \
    | SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_STATE="$1" bash "$H" >/dev/null 2>&1
}
code() { grep -oE 'approve [0-9a-f]{6}' "$1/out" | head -1 | cut -d' ' -f2; }

D=$(mktemp -d); mkdir -p "$D/scope"

begin_test "first encounter is BLOCKED and names an approval code"
[ "$(run "$D" sessA)" = 2 ] && [ -n "$(code "$D")" ] && pass || fail "not blocked or no code: $(cat "$D/out")"
C=$(code "$D")

begin_test "a retry WITHOUT the user's approval is still BLOCKED"
[ "$(run "$D" sessA)" = 2 ] && pass || fail "retry alone was allowed"

begin_test "a wrong code in the prompt grants nothing"
say "$D" sessA "approve 000000"
[ "$(run "$D" sessA)" = 2 ] && pass || fail "wrong code allowed"

begin_test "the code typed in ANOTHER session grants nothing"
say "$D" sessB "approve $C"
[ "$(run "$D" sessA)" = 2 ] && pass || fail "SESSION BYPASS: session B's prompt approved session A"

begin_test "the user's 'approve <code>' lets the retry through"
say "$D" sessA "approve $C"
[ "$(run "$D" sessA)" = 0 ] && pass || fail "approved retry blocked: $(cat "$D/out")"

begin_test "the approval is single-use"
[ "$(run "$D" sessA)" = 2 ] && pass || fail "second run rode the same approval"

begin_test "a bare 'approve' grants the one pending code"
say "$D" sessA "Approved"
[ "$(run "$D" sessA)" = 0 ] && pass || fail "bare approve did not grant"

begin_test "session B (different sid) is still BLOCKED — no cross-session bypass"
run "$D" sessA >/dev/null
[ "$(run "$D" sessB)" = 2 ] && pass || fail "SESSION BYPASS: session B allowed via session A marker"

begin_test "an ordinary prompt mentioning approve is not an approval"
run "$D" sessC >/dev/null
say "$D" sessC "can you explain how to approve a PR?"
[ "$(run "$D" sessC)" = 2 ] && pass || fail "prose approved"

# A window (memokit's change window, lightly): `approve <code> 30m` covers every
# command of that CATEGORY in this session until it expires — one approval for a
# multi-step plan. Another category, or another session, still asks.
RH2="reset --""hard HEAD~1"
run2() {
  local j; j="{\"tool_name\":\"Bash\",\"cwd\":\"/tmp\",\"session_id\":\"$2\",\"tool_input\":{\"command\":\"git $RH2\"}}"
  SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_STATE="$1" bash "$H" >"$1/out" 2>&1 <<<"$j"; echo $?
}
run "$D" sessW >/dev/null; CW=$(code "$D")
begin_test "'approve <code> 30m' opens a window: the command runs"
say "$D" sessW "approve $CW 30m"
[ "$(run "$D" sessW)" = 0 ] && pass || fail "windowed approval blocked"
begin_test "inside the window the same command runs again"
[ "$(run "$D" sessW)" = 0 ] && pass || fail "window was single-use"
begin_test "inside the window another command of the category runs"
[ "$(run2 "$D" sessW)" = 0 ] && pass || fail "window did not cover the category"
begin_test "the window is per session"
[ "$(run "$D" sessX)" = 2 ] && pass || fail "window leaked to another session"
begin_test "an expired window asks again"
for f in "$D"/scope/.gate-granted-window-sessW-*; do echo 1 > "$f"; done
[ "$(run "$D" sessW)" = 2 ] && pass || fail "expired window still allowed"
begin_test "a window longer than 4h is refused (stays single-use)"
run "$D" sessY >/dev/null; CY=$(code "$D")
say "$D" sessY "approve $CY 9h"
[ "$(run "$D" sessY)" = 0 ] && [ "$(run "$D" sessY)" = 2 ] && pass || fail "9h window accepted or approval lost"

# Only the user's prompt may write a grant: Claude forging one is selfmod.
G="$HOME/.claude/supercharger/scope/.gate-""granted-sessA-abc123def456"
guard() {  # guard <hook> <tool> <json-input-field> → deny|allow
  local j; j=$(C="$D" T="$2" V="$3" python3 -c "import json,os;t=os.environ['T'];print(json.dumps({'tool_name':t,'cwd':os.environ['C'],'session_id':'g','tool_input':{'command':os.environ['V']} if t=='Bash' else {'file_path':os.environ['V'],'content':''}}))")
  local out rc; out=$(SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/$1" <<<"$j" 2>/dev/null); rc=$?
  { [ "$rc" = 2 ] || [[ "$out" == *'"deny"'* ]]; } && echo deny || echo allow
}
begin_test "Bash: touching a grant file is denied"
[ "$(guard safety.sh Bash "touch $G")" = deny ] && pass || fail "forged grant via touch allowed"
begin_test "Bash: redirecting into a grant file is denied"
[ "$(guard safety.sh Bash ": > $G")" = deny ] && pass || fail "forged grant via redirect allowed"
# The state dir, not ~/.claude: a plugin install keeps it under $CLAUDE_PLUGIN_DATA.
begin_test "Write: creating a grant file is denied"
[ "$(guard path-guard.sh Write "$D/scope/.gate-""granted-sessA-abc123def456")" = deny ] && pass || fail "forged grant via Write allowed"

rm -rf "$D"
report
