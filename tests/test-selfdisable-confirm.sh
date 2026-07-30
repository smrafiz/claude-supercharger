#!/usr/bin/env bash
# Disabling Supercharger requires a visible confirm (v2.26.1)
#
# `sc-toggle.sh off` writes the kill-switch, after which every hook exits 0. One
# command retires every other guard, which makes it the highest-value first step for a
# prompt injection: disable, act, re-enable. Measured before this was written — the
# toggle passed harness-tamper, safety AND path-guard, and with the flag set both
# safety.sh and path-guard then allowed a settings.json write they otherwise deny.
#
# ASK, not DENY: `/sc off` is a documented user control and must keep working. What
# changes is that it can no longer happen unseen — and, critically, that an active
# autopilot window cannot swallow the confirm, since autopilot auto-approves
# everything and that is exactly when nobody is watching.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HT="$REPO_DIR/hooks/harness-tamper-guard.sh"

payload() { CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))'; }

decision() { # cmd -> ask | deny | allow
  local out rc
  out=$(payload "$1" | bash "$HT" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo deny
  elif printf '%s' "$out" | grep -q '"ask"'; then echo ask
  else echo allow; fi
}

echo "=== Self-disable Confirm Tests ==="

begin_test "sc-toggle off raises a confirm (not a silent pass)"
[ "$(decision 'bash ~/.claude/supercharger/tools/sc-toggle.sh off')" = "ask" ] && pass || fail "no confirm raised"

begin_test "the plugin-path form also raises a confirm"
[ "$(decision 'bash "${CLAUDE_PLUGIN_ROOT}"/tools/sc-toggle.sh off')" = "ask" ] && pass || fail "plugin path not covered"

begin_test "the confirm explains what is lost, not just what is happening"
OUT=$(payload 'bash tools/sc-toggle.sh off' | bash "$HT" 2>/dev/null)
printf '%s' "$OUT" | grep -qi 'every guard is inactive' && pass || fail "reason does not state the consequence"

begin_test "the confirm warns that an injection would want this step"
OUT=$(payload 'bash tools/sc-toggle.sh off' | bash "$HT" 2>/dev/null)
printf '%s' "$OUT" | grep -qi 'injected' && pass || fail "reason omits the injection framing"

begin_test "turning Supercharger ON is not gated"
[ "$(decision 'bash ~/.claude/supercharger/tools/sc-toggle.sh on')" = "allow" ] && pass || fail "/sc on should not prompt"

begin_test "sc-toggle status is not gated"
[ "$(decision 'bash ~/.claude/supercharger/tools/sc-toggle.sh status')" = "allow" ] && pass || fail "status should not prompt"

begin_test "unrelated commands are unaffected"
[ "$(decision 'ls -la')" = "allow" ] && pass || fail "over-matched an unrelated command"

begin_test "an unrelated command containing the word off is unaffected"
[ "$(decision 'git log --oneline | head -5  # kick off the release')" = "allow" ] && pass || fail "matched on the bare word off"

# --- the half that actually closes the hole ---
# shellcheck source=hooks/lib-smart-approve.sh
. "$REPO_DIR/hooks/lib-smart-approve.sh" 2>/dev/null || true

approves() { # cmd -> yes|no   (0 = would auto-approve)
  local inp
  inp=$(payload "$1")
  if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi
}

begin_test "smart-approve refuses to auto-approve the disable (plain)"
if type smart_approve_verdict >/dev/null 2>&1; then
  [ "$(approves 'bash ~/.claude/supercharger/tools/sc-toggle.sh off')" = "no" ] && pass || fail "auto-approved the disable"
else
  fail "smart_approve_verdict not available — the decline cannot be verified"
fi

begin_test "AUTOPILOT cannot swallow the confirm"
ST=$(mktemp -d); mkdir -p "$ST/scope"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$ST/scope/.autopilot-until"
GOT=$(SUPERCHARGER_STATE="$ST" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
inp=$(CMD="bash ~/.claude/supercharger/tools/sc-toggle.sh off" python3 -c "
import json,os
print(json.dumps({\"tool_name\":\"Bash\",\"tool_input\":{\"command\":os.environ[\"CMD\"]}}))")
if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi')
[ "$GOT" = "no" ] && pass || fail "autopilot auto-approved the disable (got: $GOT)"
rm -rf "$ST"

begin_test "autopilot still auto-approves an ordinary command (no over-tightening)"
ST=$(mktemp -d); mkdir -p "$ST/scope"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$ST/scope/.autopilot-until"
GOT=$(SUPERCHARGER_STATE="$ST" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
inp=$(CMD="ls -la" python3 -c "
import json,os
print(json.dumps({\"tool_name\":\"Bash\",\"tool_input\":{\"command\":os.environ[\"CMD\"]}}))")
if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi')
[ "$GOT" = "yes" ] && pass || fail "autopilot stopped approving ordinary commands (got: $GOT)"
rm -rf "$ST"

report
