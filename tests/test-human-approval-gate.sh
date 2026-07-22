#!/usr/bin/env bash
# Suite for human-approval-gate.sh pending-file scoping (v2.21.4).
# The pending-approval marker was keyed on the command hash alone, so a second
# concurrent SESSION running the same high-risk command consumed session A's
# "already asked" marker and was allowed through WITHOUT its own prompt.
# Must be session-scoped: each session clears its own gate.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/human-approval-gate.sh"

# high-risk trigger built from parts so this file doesn't trip safety.sh
RH="reset --""hard"
mkcmd() { printf 'git %s HEAD' "$RH"; }

# rc <state_dir> <session_id> → exit code (2 = blocked/asked, 0 = allowed)
rc() {
  local j; j="{\"tool_name\":\"Bash\",\"cwd\":\"/tmp\",\"session_id\":\"$2\",\"tool_input\":{\"command\":\"$(mkcmd)\"}}"
  SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_STATE="$1" bash "$H" >/dev/null 2>&1 <<<"$j"; echo $?
}

D=$(mktemp -d); mkdir -p "$D/scope"

begin_test "human-approval: first encounter (session A) is BLOCKED (exit 2)"
[ "$(rc "$D" sessA)" = 2 ] && pass || fail "first call not blocked"

begin_test "human-approval: session A retry is ALLOWED (exit 0) — user approved"
[ "$(rc "$D" sessA)" = 0 ] && pass || fail "same-session retry not allowed"

# recreate the pending marker for session A, then a DIFFERENT session runs it
rc "$D" sessA >/dev/null   # blocks + writes .gate-pending-sessA-<hash>
begin_test "human-approval: session B (different sid) is still BLOCKED — no cross-session bypass"
[ "$(rc "$D" sessB)" = 2 ] && pass || fail "SESSION BYPASS: session B allowed via session A marker"

rm -rf "$D"
report
