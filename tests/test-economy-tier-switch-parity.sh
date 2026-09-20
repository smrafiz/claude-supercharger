#!/usr/bin/env bash
# The economy tier has one owner: scope/.economy-tier (v4.1.9)
#
# Two switch paths existed and neither was complete:
#
#   tools/economy-switch.sh   rewrote the Active Tier block in economy.md,
#                             and never touched scope/.economy-tier
#   the documented phrase     "eco standard" / "eco lean" / "eco minimal" was
#                             printed in economy.md and implemented NOWHERE
#
# Every hook resolves the tier from scope/.economy-tier and only falls back to
# parsing economy.md when that file is absent. install.sh always creates it, so
# the fallback never ran: the tool's switch was invisible to economy-reinforce
# and adaptive-economy, which kept injecting the tier the scope file still named.
#
# These pin the contract rather than either implementation: whatever switches the
# tier must leave scope/.economy-tier naming the new tier, and the reinforcement
# that follows must match it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Economy tier switch parity ==="

newenv() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo minimal > "$d/scope/.economy-tier"; printf '%s' "$d"; }

# Run the reinforcement hook with a prompt; echo the resulting tier file.
hook_with() { # state_dir, prompt -> tier after
  printf '{"prompt":%s,"cwd":"%s"}' "$2" "$1" \
    | SUPERCHARGER_STATE="$1" bash "$REPO_DIR/hooks/economy-reinforce.sh" >/dev/null 2>&1
  cat "$1/scope/.economy-tier" 2>/dev/null
}

begin_test "the documented phrase switches the tier"
D=$(newenv); GOT=$(hook_with "$D" '"eco standard"')
[ "$GOT" = "standard" ] && pass || fail "expected standard, got '$GOT'"; rm -rf "$D"

begin_test "a separator other than space is accepted"
D=$(newenv); GOT=$(hook_with "$D" '"eco:lean"')
[ "$GOT" = "lean" ] && pass || fail "expected lean, got '$GOT'"; rm -rf "$D"

begin_test "case and trailing punctuation do not defeat it"
D=$(newenv); GOT=$(hook_with "$D" '"Eco Standard."')
[ "$GOT" = "standard" ] && pass || fail "expected standard, got '$GOT'"; rm -rf "$D"

# The false-positive guard is the reason this matches the WHOLE prompt. This
# file's own subject matter is the phrase, so a substring match would switch
# tiers every time someone reports a bug about it.
begin_test "discussing the phrase does not switch the tier"
D=$(newenv); GOT=$(hook_with "$D" '"the eco minimal tier is broken, can you fix it?"')
[ "$GOT" = "minimal" ] && pass || fail "a bug report switched the tier to '$GOT'"; rm -rf "$D"

begin_test "a prompt merely containing the words does not switch"
D=$(newenv); GOT=$(hook_with "$D" '"switch to eco standard when the build is green"')
[ "$GOT" = "minimal" ] && pass || fail "expected no switch, got '$GOT'"; rm -rf "$D"

begin_test "an ordinary prompt leaves the tier alone"
D=$(newenv); GOT=$(hook_with "$D" '"fix the failing test in tests/run.sh"')
[ "$GOT" = "minimal" ] && pass || fail "expected minimal, got '$GOT'"; rm -rf "$D"

# The reinforcement that follows a switch must name the NEW tier, not the old
# one — the switch is parsed before the tier is resolved for exactly this reason.
begin_test "reinforcement after a switch names the new tier"
D=$(newenv)
OUT=$(printf '{"prompt":"eco lean","cwd":"%s"}' "$D" | SUPERCHARGER_STATE="$D" bash "$REPO_DIR/hooks/economy-reinforce.sh" 2>/dev/null)
printf '%s' "$OUT" | grep -q "ECONOMY:LEAN" && pass || fail "expected LEAN reinforcement, got: ${OUT:0:120}"
rm -rf "$D"

# The tool is the other writer. It used to change economy.md only.
begin_test "the switch tool writes the scope file the hooks read"
D=$(newenv)
H=$(mktemp -d); mkdir -p "$H/.claude/rules" "$H/.claude/supercharger/economy"
for t in standard lean minimal; do cp "$REPO_DIR/configs/economy/$t.md" "$H/.claude/supercharger/economy/$t.md"; done
printf '### Active Tier: Minimal\nplaceholder\n' > "$H/.claude/rules/economy.md"
HOME="$H" SUPERCHARGER_STATE="$D" bash "$REPO_DIR/tools/economy-switch.sh" lean >/dev/null 2>&1
GOT=$(cat "$D/scope/.economy-tier" 2>/dev/null)
[ "$GOT" = "lean" ] && pass || fail "tool left the scope file at '$GOT' — hooks would keep the old tier"
rm -rf "$D" "$H"

report
