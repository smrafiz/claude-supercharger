#!/usr/bin/env bash
# Disabling a security guard requires a confirm (v2.26.23)
#
# 2.26.1 put a confirm on `sc-toggle off`. hook-toggle is the same door and was left
# open: `hook-toggle.sh <guard> off` comments the registration out of settings.json so
# the hook never fires again, it edits that file from INSIDE a tool (where path-guard
# and safety.sh never see the write), and it was agent-invokable with no confirmation.
#
# This was not theorised — it was demonstrated by accident. A probe run with an isolated
# SUPERCHARGER_STATE still hit the real config, because SETTINGS_FILE is hardcoded to
# $HOME and SUPERCHARGER_STATE does not redirect it. safety.sh, git-safety.sh and
# subagent-safety.sh were commented out of a live install in one command.
#
# Two properties are pinned here:
#   1. the AGENT cannot disable a security guard unseen (ask, and autopilot cannot
#      swallow it — autopilot auto-approves everything, which is exactly when nobody
#      is watching);
#   2. a HUMAN doing it directly is warned, since no hook is involved in that path.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HT="$REPO_DIR/hooks/harness-tamper-guard.sh"

decision() { # cmd -> ask | deny | allow
  local out rc
  out=$(printf '%s' "$(CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | bash "$HT" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo deny
  elif printf '%s' "$out" | grep -q '"ask"'; then echo ask
  else echo allow; fi
}

echo "=== hook-toggle Confirm Tests ==="

begin_test "disabling safety raises a confirm"
[ "$(decision 'bash ~/.claude/supercharger/tools/hook-toggle.sh safety off')" = "ask" ] && pass || fail "no confirm"

begin_test "disabling path-guard raises a confirm"
[ "$(decision 'bash tools/hook-toggle.sh path-guard off')" = "ask" ] && pass || fail "no confirm"

begin_test "disabling harness-tamper-guard raises a confirm"
[ "$(decision 'bash tools/hook-toggle.sh harness-tamper-guard off')" = "ask" ] && pass || fail "no confirm"

begin_test "the confirm says what is lost and offers the narrower alternative"
OUT=$(printf '%s' "$(CMD='bash tools/hook-toggle.sh safety off' python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
  | bash "$HT" 2>/dev/null)
printf '%s' "$OUT" | grep -qi 'stops firing entirely' \
  && printf '%s' "$OUT" | grep -qi 'disableSecurityCategories\|customPatterns' \
  && pass || fail "confirm lacks consequence or alternative: $OUT"

# --- must NOT add friction to ordinary housekeeping ---
begin_test "disabling a non-security hook is NOT gated"
[ "$(decision 'bash tools/hook-toggle.sh post-write-advisor off')" = "allow" ] && pass || fail "over-gated an advisory hook"

begin_test "ENABLING a security guard is not gated"
[ "$(decision 'bash tools/hook-toggle.sh safety on')" = "allow" ] && pass || fail "re-enabling should never prompt"

begin_test "listing hook status is not gated"
[ "$(decision 'bash tools/hook-toggle.sh')" = "allow" ] && pass || fail "status should not prompt"

# --- autopilot must not swallow it ---
# shellcheck source=hooks/lib-smart-approve.sh
. "$REPO_DIR/hooks/lib-smart-approve.sh" 2>/dev/null || true

begin_test "AUTOPILOT cannot auto-approve disabling a security guard"
ST=$(mktemp -d); mkdir -p "$ST/scope"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$ST/scope/.autopilot-until"
GOT=$(SUPERCHARGER_STATE="$ST" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
inp=$(CMD="bash tools/hook-toggle.sh safety off" python3 -c "
import json,os
print(json.dumps({\"tool_name\":\"Bash\",\"tool_input\":{\"command\":os.environ[\"CMD\"]}}))")
if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi')
[ "$GOT" = "no" ] && pass || fail "autopilot auto-approved it (got: $GOT)"
rm -rf "$ST"

begin_test "autopilot still auto-approves ordinary commands"
ST=$(mktemp -d); mkdir -p "$ST/scope"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$ST/scope/.autopilot-until"
GOT=$(SUPERCHARGER_STATE="$ST" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
inp=$(CMD="ls -la" python3 -c "
import json,os
print(json.dumps({\"tool_name\":\"Bash\",\"tool_input\":{\"command\":os.environ[\"CMD\"]}}))")
if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi')
[ "$GOT" = "yes" ] && pass || fail "over-tightened autopilot (got: $GOT)"
rm -rf "$ST"

# --- the tool itself ---
begin_test "hook-toggle honours SUPERCHARGER_SETTINGS_FILE (testable without live config)"
TD=$(mktemp -d)
python3 -c "
import json,sys
json.dump({'hooks':{'PreToolUse':[{'matcher':'Bash','hooks':[{'type':'command','command':'/h/hooks/safety.sh #supercharger'}]}]}}, open(sys.argv[1],'w'))" "$TD/s.json"
SUPERCHARGER_SETTINGS_FILE="$TD/s.json" bash "$REPO_DIR/tools/hook-toggle.sh" safety off >/dev/null 2>&1
python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
cmd=d['hooks']['PreToolUse'][0]['hooks'][0]['command']
sys.exit(0 if cmd.strip().startswith('#') else 1)" "$TD/s.json" && pass || fail "override ignored — cannot test without touching live config"
rm -rf "$TD"

begin_test "hook-toggle WARNS a human disabling a security guard"
TD=$(mktemp -d)
python3 -c "
import json, sys
json.dump({'hooks':{'PreToolUse':[{'matcher':'Bash','hooks':[{'type':'command','command':'/h/hooks/safety.sh #supercharger'}]}]}}, open(sys.argv[1],'w'))" "$TD/s.json"
OUT=$(SUPERCHARGER_SETTINGS_FILE="$TD/s.json" bash "$REPO_DIR/tools/hook-toggle.sh" safety off 2>&1)
printf '%s' "$OUT" | grep -qi 'security guard' && pass || fail "no warning for a human: $OUT"
rm -rf "$TD"

report
