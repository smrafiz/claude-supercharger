#!/usr/bin/env bash
# Running the suite must not write to the user's live telemetry (v2.26.32)
#
# Hooks append to the block ledger and audit log under HOME. tests/run.sh has
# always given each file its own HOME, so the SUITE was never the leak. Running a
# single file directly — `bash tests/test-foo.sh`, the ordinary way to work on
# one test — was, because it inherits the developer's real HOME.
#
# That is how 92 of 318 entries in a live ledger became test data, alongside
# ad-hoc `printf ... | bash hooks/safety.sh` probes. The SessionStart [BLOCKS]
# summary then told the user `rm -rf /` had been blocked 21 times and a
# reflog-destroying command 7 times. Neither happened. The point of that summary
# is to report what really did, so a polluted ledger is worse than none.
#
# The guard lives in tests/helpers.sh because every test sources it, and this
# canary asserts against the REAL path so it can actually observe a regression.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Telemetry Isolation Tests ==="

begin_test "helpers.sh moves HOME off the real one"
[ -n "${SUPERCHARGER_TEST_HOME:-}" ] && pass || fail "HOME was not isolated — a direct run writes to the real install"

begin_test "the isolated HOME is not the developer's real HOME"
[ "${HOME%/}" = "${SUPERCHARGER_TEST_HOME%/}" ] && pass \
  || fail "HOME is $HOME, expected the isolated $SUPERCHARGER_TEST_HOME"

begin_test "the isolated state directory actually exists"
[ -d "$HOME/.claude/supercharger/scope" ] && pass || fail "scope dir was not created"

# --- the canary --------------------------------------------------------------
# Fire a hook that is KNOWN to log a block, then assert the live ledger did not
# grow. This is checked against the real path on purpose: a test asserting
# against the isolated path would pass no matter what, which is the failure mode
# this repo keeps hitting — a check that cannot observe the bug.
# Resolved from the login home, NOT $HOME — $HOME is the isolated one by now.
LIVE_LEDGER="$(eval echo ~"$(id -un)")/.claude/supercharger/scope/.blocked-commands"

count_live() { [ -f "$LIVE_LEDGER" ] && wc -l < "$LIVE_LEDGER" | tr -d ' ' || echo 0; }

begin_test "a blocking hook does not append to the LIVE block ledger"
BEFORE=$(count_live)
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
AFTER=$(count_live)
[ "$BEFORE" = "$AFTER" ] && pass \
  || fail "live ledger grew $BEFORE -> $AFTER — the suite is polluting real telemetry"

begin_test "the block WAS recorded, in the isolated ledger"
# Guards the test above from passing for the wrong reason: if the hook silently
# stopped logging altogether, the live-ledger check would also pass.
grep -q . "$HOME/.claude/supercharger/scope/.blocked-commands" 2>/dev/null && pass \
  || fail "nothing logged anywhere — the canary above proves nothing"

begin_test "a git-safety block also stays out of the live ledger"
BEFORE=$(count_live)
printf '{"tool_name":"Bash","tool_input":{"command":"git reflog expire --expire=now --all"}}' \
  | bash "$REPO_DIR/hooks/git-safety.sh" >/dev/null 2>&1
AFTER=$(count_live)
[ "$BEFORE" = "$AFTER" ] && pass || fail "live ledger grew $BEFORE -> $AFTER"

begin_test "the audit log is isolated too"
LIVE_AUDIT="$(eval echo ~"$(id -un)")/.claude/supercharger/audit"
BEFORE_AUDIT=$(ls "$LIVE_AUDIT" 2>/dev/null | wc -l | tr -d ' ')
printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
AFTER_AUDIT=$(ls "$LIVE_AUDIT" 2>/dev/null | wc -l | tr -d ' ')
[ "$BEFORE_AUDIT" = "$AFTER_AUDIT" ] && pass || fail "audit dir grew $BEFORE_AUDIT -> $AFTER_AUDIT"

# --- the override must still work --------------------------------------------
begin_test "a test can still point SUPERCHARGER_STATE somewhere of its own"
TD=$(mktemp -d); mkdir -p "$TD/scope"
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | SUPERCHARGER_STATE="$TD" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
[ -s "$TD/scope/.blocked-commands" ] && pass || fail "inline override no longer reaches the hook"
rm -rf "$TD"

# --- run.sh must clean up ----------------------------------------------------
begin_test "run.sh sweeps the isolated home dirs"
grep -q 'sc-test-home-\*' "$REPO_DIR/tests/run.sh" && pass \
  || fail "run.sh does not sweep leftovers — they accumulate in TMPDIR"

# --- configuration isolation (v2.26.46) --------------------------------------
# SUPERCHARGER_* vars are the documented way to disable a guard. Setting one in
# ~/.claude/settings.json `env` reaches the hooks AND the shell running the
# suite, so the guard exits at its first line and its tests fail — while CI, on a
# clean environment, stays green. That misdiagnosis cost real time: 3 failures
# from SUPERCHARGER_MCP_BREAKER=0 read as a regression in unrelated work.
begin_test "helpers.sh clears ambient SUPERCHARGER_* configuration"
grep -q 'SUPERCHARGER_\[A-Za-z0-9_\]\*' "$REPO_DIR/tests/helpers.sh" && pass \
  || fail "helpers.sh no longer clears ambient config — a developer's disabled guard will fail the suite"

begin_test "a guard disabled in the environment does not fail its own tests"
OUT=$(SUPERCHARGER_MCP_BREAKER=0 bash "$REPO_DIR/tests/test-mcp-circuit-breaker.sh" "$REPO_DIR" 2>&1 | tail -1)
printf '%s' "$OUT" | grep -q '0 failed' && pass || fail "ambient disable still breaks the suite: $OUT"

begin_test "NO_NOTIFY survives the clear (run.sh relies on it)"
# If this were cleared, the suite would fire desktop notifications on every run.
grep -q 'SUPERCHARGER_NO_NOTIFY' "$REPO_DIR/tests/helpers.sh" && pass \
  || fail "NO_NOTIFY is not preserved — the suite will spam notifications"

begin_test "a test's own inline assignment still reaches the hook"
# The clear happens when helpers.sh is sourced, before tests assign anything.
H=$(mktemp -d)
OUT=$(printf '{"hook_event_name":"PostToolUse","tool_name":"mcp__x__y","tool_response":{"isError":true,"content":"429"}}' \
  | SUPERCHARGER_MCP_BREAKER=0 HOME="$H" bash "$REPO_DIR/hooks/mcp-circuit-breaker.sh" 2>&1)
FOUND=$(find "$H" -name '*mcp-health*' 2>/dev/null | wc -l | tr -d ' ')
rm -rf "$H"
[ "$FOUND" = "0" ] && pass || fail "inline SUPERCHARGER_MCP_BREAKER=0 no longer reaches the hook"

report
