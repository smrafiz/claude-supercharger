#!/usr/bin/env bash
# v4.0.44 — smart-approve must never auto-approve a call the USER'S OWN
# permissions.deny / .ask covers.
#
# Whether a hook's `allow` overrides a deny rule is undocumented (checked
# 2026-09-09). Autopilot returns 0 for everything, so if hook-allow wins, an 8h
# window suspends the user's deny list. This suite pins the OUTCOME instead of
# depending on the platform's precedence — inkatze/planwright's own conclusion
# after hitting the same unresolved question.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== smart-approve vs the user's own deny/ask rules ==="

H=$(mktemp -d); mkdir -p "$H/.claude"
ST=$(mktemp -d); mkdir -p "$ST/scope"
# an OPEN autopilot window — the state in which the swallow would happen
echo $(( $(date +%s) + 3600 )) > "$ST/scope/.autopilot-until"

rules() { printf '{"permissions":{"deny":[%s]}}' "$1" > "$H/.claude/settings.json"; }
badrules() { printf '{"permissions":{"deny":["Bash(curl *)"' > "$H/.claude/settings.json"; }
askrules() { printf '{"permissions":{"ask":[%s]}}' "$1" > "$H/.claude/settings.json"; }

# 0 = auto-approved, 1 = declined (falls through to the normal prompt)
verdict() { # $1=json payload
  HOME="$H" SUPERCHARGER_STATE="$ST" bash -c '
    . "$1/hooks/lib-smart-approve.sh"
    smart_approve_verdict "$2" && echo approved || echo declined
  ' _ "$REPO_DIR" "$1"
}
bashcall() { printf '{"session_id":"d1","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":%s}}' \
  "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"; }

# ---- CONTROLS. Without these every assertion below is satisfied by a verdict
# ---- function that declines unconditionally, which is also what a broken
# ---- sourcing path produces.
begin_test "control: with NO rules, an open autopilot window approves"
rm -f "$H/.claude/settings.json"
[ "$(verdict "$(bashcall 'echo hi')")" = approved ] && pass \
  || fail "autopilot did not approve with an empty rule set — every test below is vacuous"

begin_test "control: an unrelated deny rule still approves"
rules '"Bash(kubectl *)"'
[ "$(verdict "$(bashcall 'echo hi')")" = approved ] && pass || fail "over-declined an unrelated command"

# ---- the actual property
begin_test "a denied command is NOT auto-approved under autopilot"
rules '"Bash(curl *)"'
[ "$(verdict "$(bashcall 'curl http://x/')")" = declined ] && pass || fail "autopilot swallowed a user deny rule"

begin_test "an ASK rule is honoured too (the user wanted the prompt)"
askrules '"Bash(git push *)"'
[ "$(verdict "$(bashcall 'git push origin master')")" = declined ] && pass || fail "ask rule swallowed"

begin_test "M5: the :* suffix spelling matches"
rules '"Bash(curl:*)"'
[ "$(verdict "$(bashcall 'curl http://x/')")" = declined ] && pass || fail ":* not treated as *"

begin_test "M6: a deny on ANY subcommand of a compound covers it"
rules '"Bash(curl *)"'
[ "$(verdict "$(bashcall 'echo hi && curl http://x/')")" = declined ] && pass || fail "compound split missed"

begin_test "M7: a leading VAR=value does not evade the rule"
rules '"Bash(curl *)"'
[ "$(verdict "$(bashcall 'FOO=bar curl http://x/')")" = declined ] && pass || fail "env assignment evaded"

begin_test "MB-1: a leading wrapper does not evade the rule"
rules '"Bash(curl *)"'
[ "$(verdict "$(bashcall 'timeout 30 curl http://x/')")" = declined ] && pass || fail "wrapper evaded"

begin_test "a bare tool name covers every call to that tool"
rules '"Bash"'
[ "$(verdict "$(bashcall 'echo hi')")" = declined ] && pass || fail "bare tool rule ignored"

begin_test "a non-Bash tool is matched on its own subject"
rules '"Write(/etc/**)"'
P='{"session_id":"d1","cwd":"/tmp","tool_name":"Write","tool_input":{"file_path":"/etc/hosts"}}'
[ "$(verdict "$P")" = declined ] && pass || fail "Write rule not applied to file_path"

begin_test "fails SAFE: a malformed settings file counts as covered"
printf '{"permissions":{"deny":[' > "$H/.claude/settings.json"
[ "$(verdict "$(bashcall 'echo hi')")" = declined ] && pass || fail "unreadable rules read as 'no rules'"

begin_test "fails SAFE: a rule shape we do not model counts as covered"
rules '"Bash(curl *)","mcp__weird__thing(*)"'
P='{"session_id":"d1","cwd":"/tmp","tool_name":"mcp__weird__thing","tool_input":{"x":1}}'
[ "$(verdict "$P")" = declined ] && pass || fail "an unmodelled rule was read as clean"

# --- v4.0.45: the paths must actually REACH python ---------------------------
# v4.0.44 passed them in a space-separated env var. Git Bash rewrites POSIX paths
# into Windows spelling for a native program's ARGV but not for that, so native
# Windows python could not open the file, and the fail-safe declared every call
# covered — declining EVERYTHING whenever any deny rule existed. Only the control
# assertion above caught it; every "must decline" case passed for the wrong
# reason.
#
# The two below make that class reachable WITHOUT a Windows runner: the first
# proves the matcher is reading real file content rather than failing safe, and
# the second proves the fail-safe still engages when the file genuinely is bad.
begin_test "the matcher reads the rules, rather than failing safe on every call"
# A rule set whose ONLY entry cannot match. If the file never arrives, the
# fail-safe fires and this reads as declined — which is precisely the Windows bug.
rules '"Write(/nowhere/**)"'
[ "$(verdict "$(bashcall 'echo hi')")" = approved ] && pass \
  || fail "declined against a rule that cannot match — the file did not reach the matcher"

begin_test "a file bash CAN read but python cannot parse declines, and says why"
# The two unreadable cases are NOT the same and must not be conflated:
#   * bash cannot read it either -> the platform cannot read its own deny rules,
#     so none are in effect and approving matches what Claude Code itself does.
#     (The cheap gate greps the file; a failed grep just skips it.)
#   * bash CAN read it and python cannot -> an environment fault, which is the
#     Windows argv bug. Decline, and SAY so: silence there turns a broken path
#     handoff into "autopilot declines everything" with nothing to diagnose by.
# Malformed JSON is the reachable form of the second case on every platform.
badrules
_UR_OUT=$(HOME="$H" SUPERCHARGER_STATE="$ST" bash -c '
  . "$1/hooks/lib-smart-approve.sh"
  smart_approve_verdict "$2" && echo approved || echo declined
' _ "$REPO_DIR" "$(bashcall 'echo hi')" 2>&1)
printf '%s' "$_UR_OUT" | grep -q declined && printf '%s' "$_UR_OUT" | grep -q 'cannot read' \
  && pass || fail "expected declined + a diagnostic, got: $(printf '%s' "$_UR_OUT" | tr '\n' ' ')"

begin_test "an EMPTY deny array costs no python fork either"
# Installers write an empty deny list. A bare key test would fork python on
# every permission request for a user who has no rules at all.
rules ''
HOME="$H" SUPERCHARGER_STATE="$ST" bash -c '
  . "$1/hooks/lib-smart-approve.sh"
  _sa_user_rules_cover "$2"
' _ "$REPO_DIR" "$(bashcall 'echo hi')" && fail "claimed coverage on an empty rule set" || pass

begin_test "no rules at all costs no python fork"
rm -f "$H/.claude/settings.json"
# the cheap gate: with no settings file the matcher must not even be reached
HOME="$H" SUPERCHARGER_STATE="$ST" bash -c '
  . "$1/hooks/lib-smart-approve.sh"
  _sa_user_rules_cover "$2"
' _ "$REPO_DIR" "$(bashcall 'echo hi')" && fail "claimed coverage with no settings file" || pass

rm -rf "$H" "$ST"
report
