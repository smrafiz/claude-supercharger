#!/usr/bin/env bash
# Full subagent lifecycle — the CHAIN, not individual hooks (v2.26.56)
#
# Every subagent hook passes its own tests, and a user still lost findings twice.
# Single-hook tests cannot see the failures that live BETWEEN hooks:
#   - two hooks competing for the same output channel on one event
#   - a hook that exits non-zero and stalls the chain
#   - a payload shape one hook understands and the next does not
#
# This file drives the whole SubagentStop chain, in registration order, for every
# scenario a real subagent can produce. It exists because "each part works" was
# demonstrably not the same as "the pipeline works".
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Subagent Chain Tests ==="

# Registration order, from lib/hooks.sh. Order matters: a later hook can shadow
# an earlier one's output.
STOP_CHAIN=(
  "subagent-discovery.sh"
  "subagent-stop-check.sh"
  "subagent-report-fallback.sh"
  "subagent-report-notify.sh"
  "event-logger.sh subagent_stop"
  "agent-handoff-gate.sh"
  "subagent-cost.sh stop"
)
START_CHAIN=(
  "subagent-circuit-breaker.sh"
  "subagent-discovery.sh"
  "subagent-safety.sh"
  "subagent-cost.sh start"
)

# Runs a chain. Sets CHAIN_OUT (concatenated stdout), CHAIN_RC (worst exit code),
# CHAIN_EMITTERS (space-separated names of hooks that produced stdout).
run_chain() { # payload, state_dir, chain-name(stop|start)
  local payload="$1" st="$2" which="$3"
  local -a chain
  if [ "$which" = start ]; then chain=("${START_CHAIN[@]}"); else chain=("${STOP_CHAIN[@]}"); fi
  CHAIN_OUT=""; CHAIN_RC=0; CHAIN_EMITTERS=""
  local entry hook args out rc
  for entry in "${chain[@]}"; do
    hook="${entry%% *}"; args=""
    [ "$entry" != "$hook" ] && args="${entry#* }"
    out=$(printf '%s' "$payload" | SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/$hook" $args 2>/dev/null)
    rc=$?
    [ "$rc" -gt "$CHAIN_RC" ] && CHAIN_RC=$rc
    if [ -n "$out" ]; then
      CHAIN_OUT="${CHAIN_OUT}${out}"$'\n'
      CHAIN_EMITTERS="$CHAIN_EMITTERS $hook"
    fi
  done
}

newstate() { # [report-content] -> echoes state dir
  local st; st=$(mktemp -d); mkdir -p "$st/scope/subagent-reports"
  [ -n "${1:-}" ] && printf '%s\n' "$1" > "$st/scope/subagent-reports/ag1.md"
  printf '%s' "$st"
}

payload() { # final-message [agent_id_key] [id]
  local msg="$1" key="${2:-agent_id}" id="${3:-ag1}"
  MSG="$msg" KEY="$key" ID="$id" python3 -c '
import json, os
print(json.dumps({os.environ["KEY"]: os.environ["ID"], "agent_name": "Translator",
                  "last_assistant_message": os.environ["MSG"],
                  "session_id": "chain1", "cwd": "."}))'
}

# --- A. no hook may break the chain ------------------------------------------
# A blocking SubagentStop hook exiting non-zero can stall or abort the parent's
# handling of the subagent. None of these are guards — none should ever block.
for scenario in "Ready." "" "Done." "Standing by." "[Agent stopped]" \
                "I found three real issues in src/auth.ts:44 and fixed two." ; do
  label=$(printf '%s' "${scenario:-<empty>}" | head -c 28)
  begin_test "chain: survives final=\"$label\" without blocking"
  ST=$(newstate "RECOVERED_FINDINGS")
  run_chain "$(payload "$scenario")" "$ST" stop
  rm -rf "$ST"
  [ "$CHAIN_RC" -eq 0 ] && pass || fail "chain exited $CHAIN_RC — a SubagentStop hook blocked the parent"
done

begin_test "chain: survives a malformed (non-JSON) payload"
ST=$(newstate); run_chain 'not json at all {{{' "$ST" stop; rm -rf "$ST"
[ "$CHAIN_RC" -eq 0 ] && pass || fail "chain exited $CHAIN_RC on malformed input — must fail open"

begin_test "chain: survives an empty payload"
ST=$(newstate); run_chain '' "$ST" stop; rm -rf "$ST"
[ "$CHAIN_RC" -eq 0 ] && pass || fail "chain exited $CHAIN_RC on empty input"

begin_test "chain: survives null values in every field"
ST=$(newstate)
run_chain '{"agent_id":null,"agent_name":null,"last_assistant_message":null,"session_id":null,"cwd":null}' "$ST" stop
rm -rf "$ST"
[ "$CHAIN_RC" -eq 0 ] && pass || fail "chain exited $CHAIN_RC on null fields"

begin_test "chain: SubagentStart chain never blocks either"
ST=$(newstate); run_chain "$(payload "n/a")" "$ST" start; rm -rf "$ST"
[ "$CHAIN_RC" -eq 0 ] && pass || fail "SubagentStart chain exited $CHAIN_RC"

# --- B. the degraded path actually delivers ----------------------------------
begin_test "chain: a degraded final surfaces the recovered FINDINGS"
ST=$(newstate "MARKER_THE_ACTUAL_FINDINGS")
run_chain "$(payload "Ready.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | grep -q 'MARKER_THE_ACTUAL_FINDINGS' && pass \
  || fail "findings never reached the parent: $(printf '%s' "$CHAIN_OUT" | head -c 160)"

begin_test "chain: the findings reach the USER channel (systemMessage)"
ST=$(newstate "MARKER_THE_ACTUAL_FINDINGS")
run_chain "$(payload "Ready.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | python3 -c '
import sys, json
ok = False
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads(line)
    except Exception: continue
    if "MARKER_THE_ACTUAL_FINDINGS" in str(d.get("systemMessage","")): ok = True
sys.exit(0 if ok else 1)' && pass || fail "findings never reached systemMessage — the user still sees only the stub"

begin_test "chain: a HEALTHY final is never replaced"
ST=$(newstate "SHOULD_NOT_APPEAR")
run_chain "$(payload "I reviewed src/auth.ts:44 and found three issues worth fixing.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | grep -q 'SHOULD_NOT_APPEAR' \
  && fail "a healthy subagent's output was overwritten with a recovered report" || pass

# --- C. channel contention (the class single-hook tests cannot see) -----------
begin_test "chain: exactly ONE hook writes additionalContext on a degraded stop"
# Two hooks emitting additionalContext on the same event compete: depending on
# whether CC concatenates or takes the last, the findings can be shadowed by a
# lower-value line. subagent-cost runs LAST in registration order.
ST=$(newstate "MARKER_FINDINGS")
run_chain "$(payload "Ready.")" "$ST" stop
rm -rf "$ST"
N=$(printf '%s' "$CHAIN_OUT" | python3 -c '
import sys, json
n = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads(line)
    except Exception: continue
    if (d.get("hookSpecificOutput") or {}).get("additionalContext"): n += 1
print(n)')
[ "$N" = "1" ] && pass || fail "$N hooks emitted additionalContext — they compete for one channel"

begin_test "chain: the cost line still appears when NOT degraded"
# Suppression must be scoped to the degraded case; ordinary runs keep cost data.
ST=$(newstate)
run_chain "$(payload "Reviewed src/auth.ts:44 and found three issues worth fixing.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | grep -q '\[AGENT\]' && pass \
  || fail "cost reporting disappeared for healthy agents"

# --- D. payload key drift -----------------------------------------------------
for key in agent_id subagent_id; do
  begin_test "chain: degraded detected via '$key'"
  ST=$(newstate "MARKER_KEYDRIFT")
  run_chain "$(payload "Ready." "$key" "kd1")" "$ST" stop
  rm -rf "$ST"
  printf '%s' "$CHAIN_OUT" | grep -q 'MARKER_KEYDRIFT\|SUBAGENT REPORT' && pass \
    || fail "'$key' not honoured — key drift across CC versions loses the report"
done

begin_test "chain: no agent id at all degrades quietly (no crash, no noise)"
ST=$(newstate "X")
run_chain '{"agent_name":"T","last_assistant_message":"Ready.","session_id":"c1","cwd":"."}' "$ST" stop
rm -rf "$ST"
[ "$CHAIN_RC" -eq 0 ] && pass || fail "missing id crashed the chain (rc=$CHAIN_RC)"

# --- E. report-on-disk states -------------------------------------------------
begin_test "chain: report ABSENT still points at the recovery command"
ST=$(mktemp -d); mkdir -p "$ST/scope/subagent-reports"
run_chain "$(payload "Ready.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | grep -q 'subagent-report.sh' && pass \
  || fail "no recovery pointer when the async scraper has not written yet"

begin_test "chain: an EMPTY report file falls back to the pointer"
ST=$(mktemp -d); mkdir -p "$ST/scope/subagent-reports"; : > "$ST/scope/subagent-reports/ag1.md"
run_chain "$(payload "Ready.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | grep -q 'subagent-report.sh' && pass || fail "empty report not handled"

begin_test "chain: a HUGE report is capped, not dumped whole"
ST=$(mktemp -d); mkdir -p "$ST/scope/subagent-reports"
python3 -c "import sys; open(sys.argv[1],'w').write('X'*100000)" "$ST/scope/subagent-reports/ag1.md"
run_chain "$(payload "Ready.")" "$ST" stop
LEN=${#CHAIN_OUT}
rm -rf "$ST"
[ "$LEN" -lt 20000 ] && pass || fail "emitted $LEN chars — an unbounded report floods the parent's context"

# --- F. fan-out ---------------------------------------------------------------
begin_test "chain: 5 degraded agents in one session each record separately"
ST=$(newstate "MARKER")
for i in 1 2 3 4 5; do
  printf 'findings %s\n' "$i" > "$ST/scope/subagent-reports/fan$i.md"
  run_chain "$(payload "Ready." agent_id "fan$i")" "$ST" stop
done
N=$(wc -l < "$ST/scope/.subagent-report-chain1" 2>/dev/null | tr -d ' ' || echo 0)
rm -rf "$ST"
[ "$N" = "5" ] && pass || fail "expected 5 recorded pointers, got $N"

# --- G. hostile content -------------------------------------------------------
begin_test "chain: a report containing JSON/quotes does not corrupt the emission"
ST=$(mktemp -d); mkdir -p "$ST/scope/subagent-reports"
printf '%s\n' '{"evil":"payload"} "unbalanced \\ backslash MARKER_HOSTILE' > "$ST/scope/subagent-reports/ag1.md"
run_chain "$(payload "Ready.")" "$ST" stop
rm -rf "$ST"
printf '%s' "$CHAIN_OUT" | python3 -c '
import sys, json
bad = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: json.loads(line)
    except Exception: bad += 1
sys.exit(1 if bad else 0)' && pass || fail "report content produced invalid JSON — CC discards the whole payload"

begin_test "chain: a final message with newlines/quotes is handled"
ST=$(newstate "MARKER")
run_chain "$(payload 'Ready.
"quoted" \ backslash')" "$ST" stop
rm -rf "$ST"
[ "$CHAIN_RC" -eq 0 ] && pass || fail "multiline final message crashed the chain"

report
