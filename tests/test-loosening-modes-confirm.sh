#!/usr/bin/env bash
# The time-boxed loosening modes require a confirm (v2.26.74)
#
# v2.26.1 gated `sc-toggle off`, v2.26.23 gated `hook-toggle <guard> off`, v2.26.24
# gated `trust-mcp`. The MODES were the arm of that same regex nobody checked:
#
#   - `autopilot.sh <duration>` auto-approves EVERY permission prompt for up to 8h.
#     It is one notch below `/sc off` — the safety floor survives — but every confirm
#     not explicitly declined in lib-smart-approve is swallowed for the window.
#     Measured before this test existed: the command passed harness-tamper-guard,
#     safety and path-guard with no prompt of any kind, so the agent could silence
#     its own permission layer for a workday.
#   - `readonly.sh off` / `strict.sh off` end a restriction the USER switched on.
#
# Two properties are pinned, matching test-hook-toggle-confirm.sh:
#   1. the agent cannot loosen unseen (ask), and an ACTIVE autopilot window cannot
#      auto-approve its own extension — the case where nobody is watching;
#   2. the reverse direction (turning a mode off / a restriction on) stays frictionless.
#
# The third property is specific to this arm: matching is on the invocation SHAPE.
# `readonly` is a bash builtin and `autopilot.sh` appears in any command that greps
# the tool, so a bare-word match would reproduce the v2.24.x false-positive class
# where a verb and a target merely co-occur.
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

# Is the command auto-approved with an autopilot window already open?
autopilot_approves() { # cmd -> yes | no
  local st got
  st=$(mktemp -d); mkdir -p "$st/scope"
  printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$st/scope/.autopilot-until"
  got=$(SUPERCHARGER_STATE="$st" CMD="$1" bash -c '
. "'"$REPO_DIR"'/hooks/lib-smart-approve.sh" 2>/dev/null
inp=$(python3 -c "
import json,os
print(json.dumps({\"tool_name\":\"Bash\",\"tool_input\":{\"command\":os.environ[\"CMD\"]}}))")
if smart_approve_verdict "$inp" >/dev/null 2>&1; then echo yes; else echo no; fi')
  rm -rf "$st"
  printf '%s' "$got"
}

echo "=== Loosening-Mode Confirm Tests ==="

# --- (1) turning a mode ON / a restriction OFF is gated ---
begin_test "enabling autopilot raises a confirm"
[ "$(decision 'bash ~/.claude/supercharger/tools/autopilot.sh 8h')" = "ask" ] && pass || fail "no confirm"

begin_test "enabling autopilot globally raises a confirm"
[ "$(decision 'bash tools/autopilot.sh 30m global')" = "ask" ] && pass || fail "no confirm"

begin_test "the plugin-root form is gated too (no .claude/supercharger in the path)"
[ "$(decision 'bash ${CLAUDE_PLUGIN_ROOT}/tools/autopilot.sh 2h')" = "ask" ] && pass || fail "plugin form slipped past the fast-path gate"

begin_test "a bare-number duration is gated"
[ "$(decision 'bash tools/autopilot.sh 45')" = "ask" ] && pass || fail "no confirm"

# v2.26.82: the quote sat on the WRONG SIDE of the whitespace, so the pattern
# allowed `autopilot.sh" 8h` (meaningless) and missed `autopilot.sh "8h"` — an
# ordinary spelling that was VERIFIED to open a full 8h window. Two characters
# skipped the confirm. Found by red-teaming the guard after shipping it.
begin_test "a double-quoted duration is gated"
[ "$(decision 'bash tools/autopilot.sh "8h"')" = "ask" ] && pass || fail "quoted duration skipped the confirm"

begin_test "a single-quoted duration is gated"
[ "$(decision "bash tools/autopilot.sh '8h'")" = "ask" ] && pass || fail "quoted duration skipped the confirm"

begin_test "a quoted 'off' for readonly is gated"
[ "$(decision 'bash tools/readonly.sh "off"')" = "ask" ] && pass || fail "quoted off skipped the confirm"

begin_test "AUTOPILOT cannot auto-approve a QUOTED extension either"
[ "$(autopilot_approves 'bash tools/autopilot.sh "8h"')" = "no" ] \
  && pass || fail "the two patterns drifted — an open window renews itself unseen"

begin_test "ending read-only mode early raises a confirm"
[ "$(decision 'bash tools/readonly.sh off')" = "ask" ] && pass || fail "no confirm"

begin_test "ending strict mode early raises a confirm"
[ "$(decision 'bash tools/strict.sh off')" = "ask" ] && pass || fail "no confirm"

begin_test "the autopilot confirm says what is lost"
OUT=$(printf '%s' "$(CMD='bash tools/autopilot.sh 8h' python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
  | bash "$HT" 2>/dev/null)
printf '%s' "$OUT" | grep -qi 'auto-approved' \
  && printf '%s' "$OUT" | grep -qi 'safety hooks still block' \
  && pass || fail "confirm lacks the consequence or the surviving floor: $OUT"

# --- (2) the tightening direction stays frictionless ---
begin_test "turning autopilot OFF is not gated"
[ "$(decision 'bash tools/autopilot.sh off')" = "allow" ] && pass || fail "over-gated the tightening direction"

begin_test "autopilot status is not gated"
[ "$(decision 'bash tools/autopilot.sh status')" = "allow" ] && pass || fail "status should not prompt"

begin_test "starting read-only mode is not gated"
[ "$(decision 'bash tools/readonly.sh 2h')" = "allow" ] && pass || fail "read-only is a restriction; enabling it must not prompt"

begin_test "starting strict mode is not gated"
[ "$(decision 'bash tools/strict.sh 30m')" = "allow" ] && pass || fail "strict is a restriction; enabling it must not prompt"

# --- (3) shape-matched, not word-matched: the v2.24.x false-positive class ---
begin_test "reading the autopilot tool is not gated"
[ "$(decision 'grep -n duration tools/autopilot.sh')" = "allow" ] && pass || fail "a read-only grep was gated"

begin_test "the readonly bash builtin is not gated"
[ "$(decision 'readonly MAXLEN=80; echo "$MAXLEN"')" = "allow" ] && pass || fail "the bash builtin tripped the guard"

begin_test "reading the autopilot deadline file is not gated"
[ "$(decision 'cat ~/.claude/supercharger/scope/.autopilot-until')" = "allow" ] && pass || fail "a state read was gated"

# --- (4) an open autopilot window cannot swallow its own extension ---
# shellcheck source=hooks/lib-smart-approve.sh
. "$REPO_DIR/hooks/lib-smart-approve.sh" 2>/dev/null || true

begin_test "AUTOPILOT cannot auto-approve EXTENDING autopilot"
[ "$(autopilot_approves 'bash tools/autopilot.sh 8h')" = "no" ] && pass || fail "an open window renewed itself unseen"

begin_test "AUTOPILOT cannot auto-approve ending read-only mode"
[ "$(autopilot_approves 'bash tools/readonly.sh off')" = "no" ] && pass || fail "autopilot swallowed the confirm"

begin_test "AUTOPILOT cannot auto-approve ending strict mode"
[ "$(autopilot_approves 'bash tools/strict.sh off')" = "no" ] && pass || fail "autopilot swallowed the confirm"

begin_test "autopilot still auto-approves ordinary commands"
[ "$(autopilot_approves 'ls -la')" = "yes" ] && pass || fail "over-tightened autopilot"

begin_test "autopilot still auto-approves turning ITSELF off"
[ "$(autopilot_approves 'bash tools/autopilot.sh off')" = "yes" ] && pass || fail "the tightening direction must never need a prompt"

report
