#!/usr/bin/env bash
# A stated test result is checked against what actually ran (v2.26.31)
#
# CLAUDE.md's Verification Gate already says "run the check and confirm it
# passes". That is a prompt rule, and prompt rules are advisory. This hook is the
# enforcement half: the claim is compared against the recorded tool_result in the
# transcript, which cannot be edited after the fact.
#
# Severity is deliberately split:
#   CONTRADICTED (claim + a recorded FAILING run) -> block the stop. Unambiguous.
#   UNEVIDENCED  (claim + no run at all)          -> advisory only. The claim may
#                                                    be about CI, a prior session,
#                                                    or something the user said.
#
# Adapted from K-sushi/claude-notary's out-of-band verification WITHOUT the
# re-execution: re-running a suite on every Stop costs minutes per turn in a real
# repo (this one takes ~3), and Stop fires at the end of every assistant turn.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GATE="$REPO_DIR/hooks/claim-evidence-gate.sh"
TD=$(mktemp -d)

# Build a synthetic transcript: alternating assistant turns and tool results, in
# the shape Claude Code actually writes.
mk() { # name, python-body-appending-to `s`
  python3 - "$TD/$1.jsonl" "$2" <<'PY'
import json, sys
out, spec = sys.argv[1], sys.argv[2]
def asst(text=None, cmd=None, tid=None):
    c = []
    if text is not None: c.append({"type": "text", "text": text})
    if cmd: c.append({"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}})
    return json.dumps({"type": "assistant", "message": {"content": c}}) + "\n"
def res(tid, text, err=False):
    return json.dumps({"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": tid, "is_error": err,
         "content": [{"type": "text", "text": text}]}]}}) + "\n"
open(out, "w").write(eval(spec))
PY
}

rc_for() { # transcript name -> exit code
  printf '{"transcript_path":"%s","stop_hook_active":false}' "$TD/$1.jsonl" \
    | bash "$GATE" >/dev/null 2>&1
  echo $?
}
msg_for() { # transcript name -> stderr
  printf '{"transcript_path":"%s","stop_hook_active":false}' "$TD/$1.jsonl" \
    | bash "$GATE" 2>&1 >/dev/null
}

echo "=== Claim/Evidence Gate Tests ==="

# --- contradicted: block ----------------------------------------------------
mk contradicted 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 3040 passed, 3 failed\n  FAIL something broke") + asst(text="Fixed it. All tests pass now.")'
begin_test "claiming a pass after a failing run blocks the stop"
[ "$(rc_for contradicted)" = "2" ] && pass || fail "not blocked"

mk pytest_fail 'asst(cmd="pytest -q", tid="t1") + res("t1", "FAILED tests/test_a.py::test_b - AssertionError\n1 failed, 86 passed") + asst(text="All tests pass.")'
begin_test "pytest FAILED markers are detected"
[ "$(rc_for pytest_fail)" = "2" ] && pass || fail "not blocked"

mk nonzero 'asst(cmd="npm test", tid="t1") + res("t1", "output", err=True) + asst(text="Tests pass.")'
begin_test "a non-zero exit blocks even with no failure text"
[ "$(rc_for nonzero)" = "2" ] && pass || fail "not blocked"

begin_test "the block quotes the claim and the contradicting evidence"
OUT=$(msg_for contradicted)
printf '%s' "$OUT" | grep -q 'All tests pass now' \
  && printf '%s' "$OUT" | grep -q '3 failed' && pass || fail "message lacks claim or evidence: $OUT"

# --- clean runs must NOT block ----------------------------------------------
# THE false positive this hook shipped with and had to fix: the failure markers
# were all case-insensitive, so r"\bFAILED\b" under re.I matched the ordinary
# word "failed" inside "3043 passed, 0 failed" — a fully green run read as a
# failing one and held the session open. Uppercase runner markers must stay
# case-sensitive. These are the tests that catch a regression of that.
mk clean 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 3043 passed, 0 failed") + asst(text="Shipped. Suite is green: 3043 passed, 0 failed.")'
begin_test "a green run reporting '0 failed' does NOT block"
[ "$(rc_for clean)" = "0" ] && pass || fail "false positive on a passing run"

mk pytest_clean 'asst(cmd="pytest -q", tid="t1") + res("t1", "collected 87 items\n87 passed, 0 failed in 2.1s") + asst(text="All tests pass.")'
begin_test "pytest green output does NOT block"
[ "$(rc_for pytest_clean)" = "0" ] && pass || fail "false positive on pytest green"

mk zero_failures 'asst(cmd="make test", tid="t1") + res("t1", "Ran 40 tests. 0 failures, 0 errors") + asst(text="All tests pass.")'
begin_test "'0 failures' does NOT read as a failure"
[ "$(rc_for zero_failures)" = "0" ] && pass || fail "false positive on '0 failures'"

mk recovered 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 3040 passed, 3 failed") + asst(cmd="bash tests/run.sh", tid="t2") + res("t2", "Total: 3043 passed, 0 failed") + asst(text="Fixed. Suite is green.")'
begin_test "a failing run followed by a passing re-run does NOT block"
[ "$(rc_for recovered)" = "0" ] && pass || fail "the LAST run must be the one that counts"

# --- unevidenced: advise, never block ---------------------------------------
mk unevidenced 'asst(text="All tests pass.")'
begin_test "a claim with no test run at all does not block"
[ "$(rc_for unevidenced)" = "0" ] && pass || fail "unevidenced claims must not hold the session open"

begin_test "but it does say so"
msg_for unevidenced | grep -qi 'no test command ran' && pass || fail "no advisory emitted"

# --- non-claims -------------------------------------------------------------
mk hedged 'asst(text="Once all tests pass we can ship. I should verify the build succeeds first.")'
begin_test "hedged/conditional wording is not a claim"
[ "$(rc_for hedged)" = "0" ] && [ -z "$(msg_for hedged)" ] && pass || fail "conditional text treated as a claim"

mk noclaim 'asst(text="Refactored the parser and updated the docs.")'
begin_test "ordinary text produces nothing"
[ "$(rc_for noclaim)" = "0" ] && [ -z "$(msg_for noclaim)" ] && pass || fail "fired with no claim present"

# --- contract ---------------------------------------------------------------
begin_test "stop_hook_active short-circuits (no re-entry loop)"
GOT=$(printf '{"transcript_path":"%s","stop_hook_active":true}' "$TD/contradicted.jsonl" \
  | bash "$GATE" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "would loop forever on a blocked stop"

begin_test "a missing transcript fails open"
GOT=$(printf '{"transcript_path":"/nonexistent/nope.jsonl"}' | bash "$GATE" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "must never block when it cannot read the transcript"

begin_test "malformed JSON input fails open"
GOT=$(printf 'not json at all' | bash "$GATE" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "must fail open"

begin_test "a transcript of unparseable lines fails open"
printf 'garbage\n{broken\n' > "$TD/garbage.jsonl"
[ "$(rc_for garbage)" = "0" ] && pass || fail "must fail open"

begin_test "SUPERCHARGER_CLAIM_EVIDENCE_GATE=0 disables it"
GOT=$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$TD/contradicted.jsonl" \
  | SUPERCHARGER_CLAIM_EVIDENCE_GATE=0 bash "$GATE" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "kill switch ignored"

# --- registration -----------------------------------------------------------
begin_test "registered on Stop, synchronously (async cannot block)"
grep -q 'Stop|\*|${hooks_dir}/claim-evidence-gate.sh|"' "$REPO_DIR/lib/hooks.sh" && pass \
  || fail "not registered synchronously — an async Stop hook cannot block"

begin_test "present in the generated plugin hooks.json"
grep -q 'claim-evidence-gate' "$REPO_DIR/hooks/hooks.json" && pass \
  || fail "hooks.json is generated — run tools/gen-plugin-hooks.sh"

# --- killed runs are not failed runs (v2.26.47) -------------------------------
# `is_error` is set for ANY non-zero exit, including SIGTERM from a harness
# timeout (143) and SIGINT (130). The gate treated that as "the tests failed" and
# blocked, telling the author their green run was red. Observed live: a suite run
# cut off by a 10-minute tool timeout, immediately after a completed 3251/0.
#
# An interrupted run is NO EVIDENCE, not counter-evidence — so it downgrades to
# the advisory rather than a block. A failure that was ALSO killed still blocks.
mk killed 'asst("Running the suite.", "bash tests/run.sh", "t1") + \
  res("t1", "Exit code 143\nCommand timed out after 10m 0s\nTotal: 3251 passed, 0 failed", err=True) + \
  asst("All tests pass — the suite is green.")'

begin_test "a run killed by a timeout does NOT block a passing claim"
[ "$(rc_for killed)" = "0" ] && pass || fail "a killed run was reported as a test failure"

begin_test "and it says no result was recorded, not that tests failed"
msg_for killed | grep -qi 'no test command ran' && pass \
  || fail "wrong message for an interrupted run: $(msg_for killed)"

mk killed_sigint 'asst("Running.", "bash tests/run.sh", "t1") + \
  res("t1", "Exit code 130\nterminated by signal", err=True) + \
  asst("Tests all pass.")'
begin_test "SIGINT (130) is treated the same as a timeout"
[ "$(rc_for killed_sigint)" = "0" ] && pass || fail "Ctrl-C treated as a test failure"

mk failed_and_killed 'asst("Running.", "bash tests/run.sh", "t1") + \
  res("t1", "  FAIL something broke\nTotal: 3200 passed, 1 failed\nCommand timed out after 10m 0s", err=True) + \
  asst("All tests pass now.")'   # must match CLAIM: "everything passes" does not
begin_test "a REAL failure that was also killed still blocks"
# The exemption keys on the ABSENCE of failure markers — otherwise it would
# become a way to launder any red run into an advisory.
[ "$(rc_for failed_and_killed)" = "2" ] && pass \
  || fail "a genuine failure escaped the gate because the run was also killed"

rm -rf "$TD"
report
