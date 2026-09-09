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
