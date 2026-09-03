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

# --- v2.29.27: a PASS line is not failure evidence, whatever its NAME says ------
# KNOWN-ISSUES #3, first false positive. FAIL_UPPER matched "FAILED" inside the
# TEST NAME on this suite's own green line, so a run reporting 0 failures read as
# failing and the block quoted a passing line as its proof. The marker is coloured
# in real output, so the fixture carries ANSI too -- without stripping, the PASS
# prefix never matches and this test would pass for the wrong reason.
mk green_name_says_failed 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "  \x1b[0;32mPASS\x1b[0m pytest FAILED markers are detected\nTotal: 3905 passed, 0 failed") + asst(text="All tests pass.")'
begin_test "a green run whose test NAME contains FAILED does not block"
[ "$(rc_for green_name_says_failed)" = "0" ] && pass \
  || fail "blocked on a passing run: $(msg_for green_name_says_failed | head -3)"

# The same shape must still block when the run ACTUALLY failed — the fix must not
# turn the presence of any PASS line into a laundering route for a red run.
mk real_fail_with_pass_lines 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "  \x1b[0;32mPASS\x1b[0m pytest FAILED markers are detected\n  \x1b[0;31mFAIL\x1b[0m the thing broke\nTotal: 3904 passed, 1 failed") + asst(text="All tests pass.")'
begin_test "a red run containing PASS lines still blocks"
[ "$(rc_for real_fail_with_pass_lines)" = "2" ] && pass \
  || fail "a genuine failure was laundered by the PASS-line exemption"

begin_test "the quoted evidence is a failing line, not a passing one"
msg_for real_fail_with_pass_lines | grep -q 'FAILED markers are detected' \
  && fail "quoted a PASSING line as proof of failure" || pass

# --- v2.29.27: a sentence that DISCLAIMS a figure is not a claim ---------------
# KNOWN-ISSUES #3, second false positive. The sentence's whole point was that the
# quoted count does NOT hold on a clean checkout; the gate read it as an assertion
# that it does. Note the gate was substantively right that the run was red, which
# is what made the mechanism easy to overlook.
mk disclaimed 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 3888 passed, 1 failed\n  FAIL clean-tree only") + asst(text="The entry reads 3889 tests passing; that is accurate the way it was measured, and wrong in a clean checkout.")'
begin_test "a sentence disclaiming a count is not treated as a passing claim"
[ "$(rc_for disclaimed)" = "0" ] && pass \
  || fail "fired on a sentence that retracted the figure"

# The retraction exemption must not become a bypass: saying "wrong" anywhere in a
# turn cannot excuse a separate, unhedged claim in its own sentence.
mk disclaim_plus_claim 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 3888 passed, 1 failed\n  FAIL clean-tree only") + asst(text="My earlier count was wrong. All tests pass now.")'
begin_test "a retraction elsewhere does not excuse a real claim"
[ "$(rc_for disclaim_plus_claim)" = "2" ] && pass \
  || fail "the disclaimer exemption leaked across sentences"

# --- v2.29.29: a test command that ran NOTHING is not evidence -----------------
# From ggwhite/4x's ac_checks linter, which rejects `true`/`echo`/bare `grep` as
# verification because a check must EXECUTE the thing under test. Our version of
# that hole: an invocation that collects, deselects or finds nothing MATCHES
# TEST_CMD, exits 0 and reports no failures -- so the gate read it as a green run.
# Advisory tier, never a block: the run did not fail, it proved nothing, which is
# the same standing as no run at all.
zt() { # transcript name -> ADVISORY | SILENT | BLOCK
  local rc msg
  msg=$(msg_for "$1"); rc=$(rc_for "$1")
  if [ "$rc" = "2" ]; then echo BLOCK
  elif printf '%s' "$msg" | grep -q 'executed NO tests'; then echo ADVISORY
  else echo SILENT; fi
}

mk zt_collect_only 'asst(cmd="pytest --collect-only", tid="t1") + res("t1", "collected 42 items\n\n42 tests collected in 0.12s") + asst(text="All tests pass.")'
begin_test "pytest --collect-only is not evidence of a passing suite"
[ "$(zt zt_collect_only)" = "ADVISORY" ] && pass || fail "got $(zt zt_collect_only)"

mk zt_deselected 'asst(cmd="pytest -k nosuchtest", tid="t1") + res("t1", "collected 42 items / 42 deselected\n\n42 deselected in 0.10s") + asst(text="All tests pass.")'
begin_test "a run where everything was deselected is not evidence"
[ "$(zt zt_deselected)" = "ADVISORY" ] && pass || fail "got $(zt zt_deselected)"

mk zt_go_norun 'asst(cmd="go test -run XXXNoSuchTest ./...", tid="t1") + res("t1", "ok  \tgithub.com/x/y\t0.002s [no tests to run]") + asst(text="All tests pass.")'
begin_test "go test matching no tests is not evidence"
[ "$(zt zt_go_norun)" = "ADVISORY" ] && pass || fail "got $(zt zt_go_norun)"

mk zt_passwithnotests 'asst(cmd="npm test -- --passWithNoTests", tid="t1") + res("t1", "No tests found, exiting with code 0") + asst(text="All tests pass.")'
begin_test "--passWithNoTests is not evidence"
[ "$(zt zt_passwithnotests)" = "ADVISORY" ] && pass || fail "got $(zt zt_passwithnotests)"

mk zt_zero_total 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 0 passed, 0 failed") + asst(text="All tests pass.")'
begin_test "a suite reporting 0 passed 0 failed is not evidence"
[ "$(zt zt_zero_total)" = "ADVISORY" ] && pass || fail "got $(zt zt_zero_total)"

# --- precision: real runs, however small, must stay silent ---------------------
mk zt_one_passed 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 1 passed, 0 failed") + asst(text="All tests pass.")'
begin_test "a genuine one-test run is still evidence"
[ "$(zt zt_one_passed)" = "SILENT" ] && pass || fail "fired on a real run: $(zt zt_one_passed)"

# Guards the lookbehind: "10 passed, 0 failed" contains the substring "0 passed".
mk zt_ten_passed 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 10 passed, 0 failed") + asst(text="All tests pass.")'
begin_test "10 passed is not misread as 0 passed"
[ "$(zt zt_ten_passed)" = "SILENT" ] && pass || fail "lookbehind failed: $(zt zt_ten_passed)"

mk zt_real_green 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 3929 passed, 0 failed") + asst(text="All tests pass.")'
begin_test "a real green suite stays silent"
[ "$(zt zt_real_green)" = "SILENT" ] && pass || fail "fired on a green run"

# --- anti-bypass: ran nothing AND failed is a FAILING run, not an advisory ------
# The zero-test exemption must not become a way to soften a red run into a note.
mk zt_zero_and_failed 'asst(cmd="bash tests/run.sh", tid="t1") + res("t1", "Total: 0 passed, 0 failed\n  FAIL the harness died") + asst(text="All tests pass.")'
begin_test "a run that failed AND ran nothing still blocks"
[ "$(zt zt_zero_and_failed)" = "BLOCK" ] && pass || fail "a red run was softened to advisory"

# --- v4.0.22: completion claimed while the turn wrote a placeholder -----------
# CLAUDE.md's verification gate level 2 ("real implementation, not placeholder —
# no TODO, FIXME, stubs") was prose with no mechanism. Same contradiction shape
# as the test-claim arm, different evidence: the code the turn itself wrote.
# Scoping is the whole design — a repo's existing TODO backlog must never fire,
# only a marker THIS turn added that is STILL on disk.
mkw() { # name, file, written-content, claim, [prevturn]
  python3 - "$TD/$1.jsonl" "$2" "$3" "$4" "${5:-}" <<'PY'
import json, sys
out, path, content, claim, prevturn = sys.argv[1:6]
def j(o): return json.dumps(o)
lines = [j({"type": "user", "message": {"content": "do the thing"}}),
         j({"type": "assistant", "message": {"content": [
             {"type": "tool_use", "id": "w1", "name": "Write",
              "input": {"file_path": path, "content": content}}]}})]
if prevturn:
    lines.append(j({"type": "user", "message": {"content": "now finish up"}}))
lines.append(j({"type": "assistant", "message": {"content": [
    {"type": "text", "text": claim}]}}))
open(out, "w").write("\n".join(lines) + "\n")
PY
}
mke() { # name, file, old_string, new_string, claim
  python3 - "$TD/$1.jsonl" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
out, path, old, new, claim = sys.argv[1:6]
def j(o): return json.dumps(o)
open(out, "w").write("\n".join([
    j({"type": "user", "message": {"content": "do the thing"}}),
    j({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "e1", "name": "Edit",
         "input": {"file_path": path, "old_string": old, "new_string": new}}]}}),
    j({"type": "assistant", "message": {"content": [{"type": "text", "text": claim}]}}),
]) + "\n")
PY
}

STUB=$'def parse(s):\n    # TODO: handle escapes\n    return s\n'
printf '%s' "$STUB" > "$TD/parser.py"

mkw ph_block "$TD/parser.py" "$STUB" "Done — the parser is fully implemented."
begin_test "claiming completion with a TODO this turn wrote blocks the stop"
[ "$(rc_for ph_block)" = "2" ] && pass || fail "not blocked: $(msg_for ph_block)"

begin_test "the block quotes the file and the placeholder line"
OUT=$(msg_for ph_block)
printf '%s' "$OUT" | grep -q 'parser.py' \
  && printf '%s' "$OUT" | grep -q 'TODO: handle escapes' && pass \
  || fail "message lacks file or line: $OUT"

# The honest sequence this must not punish: write a stub, replace it later in the
# same turn, then say it is done — because by then it is. The disk read is what
# separates that from the real thing, so removing it must redden a test.
printf 'def parse(s):\n    return unescape(s)\n' > "$TD/fixed.py"
mkw ph_removed "$TD/fixed.py" "$STUB" "Done — fully implemented."
begin_test "a placeholder written then removed in the same turn does NOT block"
[ "$(rc_for ph_removed)" = "0" ] && pass || fail "blocked on a marker no longer on disk"

printf '%s' "$STUB" > "$TD/notes.md"
mkw ph_prose "$TD/notes.md" "$STUB" "Done — fully implemented."
begin_test "a TODO in a markdown file is a note, not a stub"
[ "$(rc_for ph_prose)" = "0" ] && pass || fail "fired on prose"

# An Edit's new_string carries unchanged surrounding context. A marker present in
# BOTH sides was not introduced by this turn.
printf '%s' "$STUB" > "$TD/carried.py"
mke ph_carried "$TD/carried.py" "$STUB" "$STUB" "All done — implementation is complete."
begin_test "a marker carried through unchanged Edit context does NOT block"
[ "$(rc_for ph_carried)" = "0" ] && pass || fail "blamed an Edit for a pre-existing marker"

mkw ph_noclaim "$TD/parser.py" "$STUB" "Wrote the first pass of the parser."
begin_test "writing a TODO without claiming completion is silent"
[ "$(rc_for ph_noclaim)" = "0" ] && [ -z "$(msg_for ph_noclaim)" ] && pass \
  || fail "mid-work stubs must not fire every turn"

mkw ph_prevturn "$TD/parser.py" "$STUB" "That's done — nothing left to do." prevturn
begin_test "a marker from a PREVIOUS turn does not block this turn's claim"
[ "$(rc_for ph_prevturn)" = "0" ] && pass || fail "turn scoping leaked across the user message"

mkw ph_hedged "$TD/parser.py" "$STUB" "Once the escapes are handled this is done."
begin_test "hedged completion wording is not a claim"
[ "$(rc_for ph_hedged)" = "0" ] && pass || fail "conditional text treated as a completion claim"

begin_test "SUPERCHARGER_PLACEHOLDER_CLAIM=0 disables the arm alone"
GOT=$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$TD/ph_block.jsonl" \
  | SUPERCHARGER_PLACEHOLDER_CLAIM=0 bash "$GATE" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "arm kill switch ignored"

begin_test "and the test-claim arm still works with it off"
GOT=$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$TD/contradicted.jsonl" \
  | SUPERCHARGER_PLACEHOLDER_CLAIM=0 bash "$GATE" >/dev/null 2>&1; echo $?)
[ "$GOT" = "2" ] && pass || fail "the arm switch disabled the whole hook"

# The bash fast-path grep gates everything below it: an arm whose wording never
# reaches the python is dead code that its own tests still pass ([[two-gate-trap]]).
begin_test "the fast-path grep admits completion wording, not just test wording"
printf '%s' "$STUB" > "$TD/fastpath.py"
mkw ph_fastpath "$TD/fastpath.py" "$STUB" "Fully implemented."
[ "$(rc_for ph_fastpath)" = "2" ] && pass \
  || fail "the completion claim never got past the tail grep"

rm -rf "$TD"
report
