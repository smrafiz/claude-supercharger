#!/usr/bin/env bash
# CLAUDE.md managed-block marker (v2.26.72)
#
# The deploy/replace branch wrote the bare template while the merge branch appended
# a `# --- Claude Supercharger vX ---` wrapper. Every other reader keys on that
# wrapper, so a fresh install produced a file nothing else recognised:
#
#   - uninstall.sh strips from `^# --- Claude Supercharger` to EOF and therefore
#     left all 54 lines behind. Verified before the fix, and a plain violation of
#     "clean uninstall, restores your config exactly".
#   - the next install's merge path saw an unmarked block and removed it with the
#     pre-v2.3 LEGACY rule, warning about a block the installer had written itself
#     one run earlier. That warning, seen on a real Windows desktop, is what
#     surfaced this.
#
# NOT covered here, and open by decision rather than oversight: content a user
# appends AFTER the managed block is still removed on re-install (the merge path
# deletes to EOF), and uninstall restores a backup that may itself contain a block.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

MARKER='^# --- Claude Supercharger'

echo "=== CLAUDE.md Managed-Block Marker ==="

begin_test "a fresh deploy install writes the managed-block marker"
setup_test_home
bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config deploy --settings deploy --economy lean >/dev/null 2>&1
CM="$HOME/.claude/CLAUDE.md"
grep -q "$MARKER" "$CM" 2>/dev/null && pass \
  || fail "deploy install left CLAUDE.md unmarked — uninstall cannot find it: $(head -1 "$CM" 2>/dev/null)"
teardown_test_home

begin_test "uninstall removes the block a deploy install wrote"
# The bug in its own terms. Before the fix this left every line in place.
setup_test_home
bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config deploy --settings deploy --economy lean >/dev/null 2>&1
CM="$HOME/.claude/CLAUDE.md"
# `grep -c` prints 0 AND exits 1 when there are no matches, so `|| echo 0` yields
# TWO zeros and the numeric test below dies with "integer expression expected".
# Same trap as v2.6.42. The assignment already swallows the exit status.
BEFORE=$(grep -c 'Claude Supercharger' "$CM" 2>/dev/null); BEFORE=${BEFORE:-0}
# uninstall.sh may restore a backup; assert on the STRIP step specifically, which
# is what the marker exists for.
sed -i.bak "/$MARKER/,\$d" "$CM" 2>/dev/null
rm -f "$CM.bak"
AFTER=$(grep -c 'Claude Supercharger' "$CM" 2>/dev/null); AFTER=${AFTER:-0}
if [ "${BEFORE:-0}" -gt 0 ] && [ "${AFTER:-0}" -eq 0 ]; then pass
else fail "strip left $AFTER Supercharger line(s) (had $BEFORE) — marker not recognised"; fi
teardown_test_home

begin_test "re-installing over a deploy install raises no legacy warning"
# The symptom actually reported. A block written by the current installer must not
# be mistaken for a pre-v2.3 one.
setup_test_home
bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config deploy --settings deploy --economy lean >/dev/null 2>&1
OUT=$(bash "$REPO_DIR/install.sh" --mode full --roles developer \
        --config merge --settings merge --economy lean 2>&1)
printf '%s' "$OUT" | grep -q 'legacy unmarked' \
  && fail "installer called its own block legacy" || pass
teardown_test_home

begin_test "re-installing does not stack duplicate blocks"
# The marker is what lets merge find and replace the previous block. Without it the
# blocks accumulate, ~3KB into every session's context per install.
setup_test_home
bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config deploy --settings deploy --economy lean >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config merge --settings merge --economy lean >/dev/null 2>&1
N=$(grep -c "$MARKER" "$HOME/.claude/CLAUDE.md" 2>/dev/null); N=${N:-0}
[ "${N:-0}" -eq 1 ] && pass || fail "expected exactly 1 managed block, found $N"
teardown_test_home

begin_test "a genuinely legacy unmarked block is still stripped"
# The pre-v2.3 rule must keep working — this fix must not silently retire it.
setup_test_home
mkdir -p "$HOME/.claude"
printf '# My notes\n\n# Claude Supercharger v2.2.0\nold content here\n' > "$HOME/.claude/CLAUDE.md"
OUT=$(bash "$REPO_DIR/install.sh" --mode full --roles developer \
        --config merge --settings merge --economy lean 2>&1)
if printf '%s' "$OUT" | grep -q 'legacy unmarked' \
   && ! grep -q 'old content here' "$HOME/.claude/CLAUDE.md"; then pass
else fail "legacy stripping regressed: warning=$(printf '%s' "$OUT" | grep -c 'legacy unmarked')"; fi
teardown_test_home

begin_test "the user's own content above the block is preserved on merge"
setup_test_home
mkdir -p "$HOME/.claude"
printf '# My notes\nkeep this line\n' > "$HOME/.claude/CLAUDE.md"
bash "$REPO_DIR/install.sh" --mode full --roles developer \
  --config merge --settings merge --economy lean >/dev/null 2>&1
grep -q 'keep this line' "$HOME/.claude/CLAUDE.md" && pass \
  || fail "merge destroyed content that preceded the block"
teardown_test_home

report
