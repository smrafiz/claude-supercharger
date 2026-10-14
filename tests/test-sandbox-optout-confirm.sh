#!/usr/bin/env bash
# A Bash call that opts out of the Claude Code sandbox needs a confirm (2026-10-14)
#
# The Bash tool's sandbox opt-out becomes a permission prompt, and an open autopilot
# window approves every prompt. harness-tamper-guard ASKs, and lib-smart-approve must
# decline it before the autopilot loop or the confirm never reaches the user.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HT="$REPO_DIR/hooks/harness-tamper-guard.sh"
FLAG="dangerously""DisableSandbox"

payload() { # cmd, flag-value -> tool input json
  CMD="$1" V="$2" F="$FLAG" python3 -c '
import json, os
ti = {"command": os.environ["CMD"]}
if os.environ["V"]: ti[os.environ["F"]] = os.environ["V"] == "true"
print(json.dumps({"tool_name": "Bash", "tool_input": ti}))'
}

decision() { # cmd, flag-value
  local out rc
  out=$(payload "$1" "$2" | bash "$HT" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo deny
  elif printf '%s' "$out" | grep -q '"ask"'; then echo ask
  else echo allow; fi
}

autopilot_approves() { # cmd, flag-value -> yes | no
  local st got
  st=$(mktemp -d); mkdir -p "$st/scope"
  printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$st/scope/.autopilot-until"
  got=$(INP="$(payload "$1" "$2")" SUPERCHARGER_STATE="$st" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
if smart_approve_verdict "$INP" >/dev/null 2>&1; then echo yes; else echo no; fi')
  rm -rf "$st"
  printf '%s' "$got"
}

echo "=== Sandbox Opt-out Confirm Tests ==="

begin_test "a command run outside the sandbox raises a confirm"
[ "$(decision 'npm test' true)" = "ask" ] && pass || fail "no confirm"

begin_test "the confirm names the command"
OUT=$(payload 'npm test' true | bash "$HT" 2>/dev/null)
printf '%s' "$OUT" | grep -q 'OUTSIDE the Claude Code sandbox' && printf '%s' "$OUT" | grep -q 'npm test' \
  && pass || fail "confirm text: $OUT"

begin_test "the flag set to false is not gated"
[ "$(decision 'npm test' false)" = "allow" ] && pass || fail "false flag prompted"

begin_test "no flag is not gated"
[ "$(decision 'npm test' '')" = "allow" ] && pass || fail "plain command prompted"

begin_test "AUTOPILOT cannot auto-approve leaving the sandbox"
[ "$(autopilot_approves 'ls -la' true)" = "no" ] && pass || fail "autopilot swallowed the confirm"

begin_test "autopilot still auto-approves the same command inside the sandbox"
[ "$(autopilot_approves 'ls -la' '')" = "yes" ] && pass || fail "over-tightened autopilot"

report
