#!/usr/bin/env bash
# Agent-eval harness self-check (v2.26.11).
#
# tests/eval-agents.sh is excluded from the suite because a run costs real API
# tokens (~$3.60 budgeted). That exclusion is now the third place a real defect has
# hidden — the other two were in fuzz-safety.sh, also excluded — so the harness
# gets the same treatment: its failure modes are pinned, cheaply, with a stub
# `claude` on PATH so nothing is spent.
#
# All three defects here shared one shape with the fuzzer's: the harness could not
# tell "I could not run" from "everything failed", and could report success having
# measured nothing.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

EVAL="$REPO_DIR/tests/eval-agents.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

echo "=== Agent Eval Harness Self-Check ==="

# A sandbox repo: the script resolves REPO_DIR from its own location, so a copy
# plus the two directories it reads is a complete environment.
sandbox() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/tests/eval-prompts" "$d/configs/agents" "$d/bin"
  cp "$EVAL" "$d/tests/eval-agents.sh"
  printf 'x\n' > "$d/configs/agents/debugger.md"
  # Stub CLI: costs nothing, and returns text that matches nothing, so any
  # assertion below is about the harness's control flow, not about scoring.
  printf '#!/usr/bin/env bash\necho "stub response"\n' > "$d/bin/claude"
  chmod +x "$d/bin/claude"
  printf '%s' "$d"
}

begin_test "eval: aborts when the claude CLI is absent (does not report 9 failures)"
SB=$(sandbox)
printf '{"scenarios":[{"name":"s","prompt":"p","must_contain":["x"],"must_not_contain":[]}]}' \
  > "$SB/tests/eval-prompts/debugger.json"
OUT=$(PATH=/usr/bin:/bin bash "$SB/tests/eval-agents.sh" --agent debugger 2>&1); RC=$?
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'claude CLI is not on PATH'; then
  pass
else
  fail "expected abort rc=3 naming the CLI; got rc=$RC out=$OUT"
fi
rm -rf "$SB"

begin_test "eval: aborts when there are no prompts to score"
SB=$(sandbox)
OUT=$(PATH="$SB/bin:$PATH" bash "$SB/tests/eval-agents.sh" --agent debugger 2>&1); RC=$?
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'no eval prompts'; then
  pass
else
  fail "expected abort rc=3 on an empty prompts dir; got rc=$RC out=$OUT"
fi
rm -rf "$SB"

begin_test "eval: a malformed prompts file is NAMED as unreadable, not scored as failure"
# Asserts the guard's own message, not the word FAIL. An earlier version of this
# test accepted any FAIL and so passed against the unfixed harness too — on macOS
# the broken path reaches "0/2 scenarios passed", which contains FAIL and exits
# non-zero for entirely the wrong reason. Decoration, exactly the fault this file
# exists to prevent.
#
# The underlying bug was platform-dependent, which is why the weak assertion held:
# `seq 0 $((count-1))` with count empty becomes `seq 0 -1`, and BSD seq prints TWO
# values (0 and -1) while GNU seq prints none. So on Linux the loop was skipped,
# agent_total stayed 0, and `0 -eq 0` scored the agent as PASSED having evaluated
# nothing; on macOS it ran two bogus iterations and failed by accident. CI is ubuntu.
SB=$(sandbox)
printf 'not json {' > "$SB/tests/eval-prompts/debugger.json"
OUT=$(PATH="$SB/bin:$PATH" bash "$SB/tests/eval-agents.sh" --agent debugger 2>&1); RC=$?
if printf '%s' "$OUT" | grep -q 'unreadable or empty prompts file' && [ "$RC" != "0" ]; then
  pass
else
  fail "unreadable prompts file not identified as such: rc=$RC out=$OUT"
fi
rm -rf "$SB"

begin_test "eval: a run that scores nothing exits 3 (refusal), not merely non-zero"
# Exit 3 is the harness's "I could not measure" code, distinct from 1 = "agents
# failed". Asserting the exact code is what makes this discriminate: the unfixed
# harness also exits non-zero here on macOS, for the wrong reason.
SB=$(sandbox)
printf '{"scenarios":[]}' > "$SB/tests/eval-prompts/debugger.json"
PATH="$SB/bin:$PATH" bash "$SB/tests/eval-agents.sh" --agent debugger >/dev/null 2>&1
[ "$?" -eq 3 ] && pass || fail "zero scenarios scored must exit 3, got $?"
rm -rf "$SB"

begin_test "eval: a missing prompts file is counted, not silently dropped"
# It used to `return` without touching a counter, so the agent vanished from the
# totals — and every file missing produced "0 total" with exit 0.
SB=$(sandbox)
printf '{"scenarios":[{"name":"s","prompt":"p","must_contain":["stub"],"must_not_contain":[]}]}' \
  > "$SB/tests/eval-prompts/debugger.json"
printf 'x\n' > "$SB/configs/agents/reviewer.md"
OUT=$(PATH="$SB/bin:$PATH" bash "$SB/tests/eval-agents.sh" 2>&1)
printf '%s' "$OUT" | grep -q 'skipped' && pass || fail "skipped agents absent from the summary: $OUT"
rm -rf "$SB"

begin_test "eval: a run with no detail lines still prints a summary (bash 3.2 empty array)"
# `"${DETAIL_LINES[@]}"` on an EMPTY array is an unbound-variable error under
# `set -u` on bash 3.2 — the macOS default and this project's floor. Any run that
# scored nothing died at the details loop with exit 1, before the summary and
# before the refusal, so the harness could not even report that it had reported
# nothing. Found only because the exit-3 assertion above kept seeing exit 1.
SB=$(sandbox)
printf '{"scenarios":[]}' > "$SB/tests/eval-prompts/debugger.json"
OUT=$(PATH="$SB/bin:$PATH" bash "$SB/tests/eval-agents.sh" --agent debugger 2>&1)
printf '%s' "$OUT" | grep -q 'Scenarios:' && pass || fail "died before the summary: $OUT"
rm -rf "$SB"

begin_test "eval: never writes to live Supercharger state"
# The hooks fire inside the agent runs, so an unisolated eval writes synthetic
# events into .blocked-commands and events.log — the pollution fixed for the
# fuzzer in 2.26.10.
SB=$(sandbox)
printf '{"scenarios":[{"name":"s","prompt":"p","must_contain":["stub"],"must_not_contain":[]}]}' \
  > "$SB/tests/eval-prompts/debugger.json"
SENTINEL=$(mktemp -d); mkdir -p "$SENTINEL/scope"
printf 'pre-existing\n' > "$SENTINEL/scope/.blocked-commands"
PATH="$SB/bin:$PATH" SUPERCHARGER_STATE="$SENTINEL" \
  bash "$SB/tests/eval-agents.sh" --agent debugger >/dev/null 2>&1
LIVE=$(wc -l < "$SENTINEL/scope/.blocked-commands" | tr -d ' ')
[ "$LIVE" = "1" ] && pass || fail "harness wrote to live state: sentinel 1 -> $LIVE lines"
rm -rf "$SB" "$SENTINEL"

report
