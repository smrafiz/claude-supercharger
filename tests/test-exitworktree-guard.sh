#!/usr/bin/env bash
# ExitWorktree guard (#436)
#
# ExitWorktree action=remove + discard_changes=true deletes a worktree together
# with its uncommitted files and unmerged commits -- the tool-channel twin of
# `git worktree remove --force`, which git-safety already ASKs on. The tool call
# never touches Bash, so no guard saw it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/exitworktree-guard.sh"

echo "=== ExitWorktree Guard Tests ==="

_ewt() { # tool_input json -> stdout of the guard; RC set
  OUT=$(printf '{"tool_name":"ExitWorktree","cwd":"/tmp","tool_input":%s}' "$1" | bash "$GUARD" 2>/dev/null); RC=$?
}

begin_test "ExitWorktree remove + discard_changes=true asks"
_ewt '{"action":"remove","discard_changes":true}'
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision":"ask"' \
  && printf '%s' "$OUT" | grep -q 'Supercharger:' && pass || fail "rc=$RC out=$OUT"

begin_test "ExitWorktree remove without discard_changes is silent"
_ewt '{"action":"remove"}'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass || fail "rc=$RC out=$OUT"

begin_test "ExitWorktree remove + discard_changes=false is silent"
_ewt '{"action":"remove","discard_changes":false}'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass || fail "rc=$RC out=$OUT"

begin_test "ExitWorktree keep (even with discard_changes=true) is silent"
_ewt '{"action":"keep","discard_changes":true}'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass || fail "rc=$RC out=$OUT"

begin_test "registered on PreToolUse|ExitWorktree"
grep -q 'PreToolUse|ExitWorktree|.*exitworktree-guard.sh' "$REPO_DIR/lib/hooks.sh" && pass || fail "not registered"

begin_test "generated hooks.json carries the registration"
grep -q 'exitworktree-guard' "$REPO_DIR/hooks/hooks.json" && pass || fail "run tools/gen-plugin-hooks.sh"

begin_test "hook is executable"
[ -x "$GUARD" ] && pass || fail "not executable"

report
