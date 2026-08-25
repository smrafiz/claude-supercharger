#!/usr/bin/env bash
# release.sh: declining the commit must leave NO trace (v2.26.75)
#
# The script has two confirms. The first is free — nothing is written yet. The second
# ("commit these N files?") came AFTER the version bump, the CHANGELOG prepend and
# `git add -A`, and declining it exited 0 with all of that still in the tree. The
# message said "'git reset' to unstage", which unstages without reverting the bump.
#
# The failure that follows is silent and ships wrong content: the next run reads the
# already-bumped VERSION as CURRENT, so it produces v+2 — and v+2's commit carries
# v+1's changes. Hit for real while releasing v2.26.74, where the recovery was to
# hand-roll the commit/tag/push rather than re-run.
#
# Same family as [[silent-success-tooling]]: the tool exits 0 having done half the job.
#
# These tests drive the REAL script against a throwaway git repo — a mocked release
# would not have caught the original bug, because the bug was in the ordering of the
# real script's side effects.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# A minimal repo with the six files release.sh rewrites, plus a passing test suite.
make_fixture() { # -> prints the fixture path
  local d; d=$(mktemp -d)
  mkdir -p "$d/lib" "$d/tools" "$d/tests" "$d/.claude-plugin"
  printf 'VERSION="1.2.3"\n'                     > "$d/lib/utils.sh"
  printf 'VERSION="1.2.3"\n'                     > "$d/tools/supercharger.sh"
  printf 'version-1.2.3-blue tests-10%%20passing\n' > "$d/README.md"
  printf '# Changelog\n\n- [1.2.3] - 2020-01-01 — previous.\n' > "$d/CHANGELOG.md"
  printf '{"version": "1.2.3"}\n'                > "$d/.claude-plugin/plugin.json"
  printf '{"version": "1.2.3"}\n'                > "$d/.claude-plugin/marketplace.json"
  printf '#!/usr/bin/env bash\necho "Total: 10 passed, 0 failed"\nexit 0\n' > "$d/tests/run.sh"
  cp "$REPO_DIR/tools/release.sh" "$d/tools/release.sh"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm init >/dev/null 2>&1
  printf '%s' "$d"
}

echo "=== release.sh Abort-Safety Tests ==="

# --- declining the commit reverts everything ---
FIX=$(make_fixture)
printf 'y\nn\n' | bash "$FIX/tools/release.sh" patch -m "test" >/dev/null 2>&1 || true

begin_test "declining the commit reverts the VERSION bump"
grep -q 'VERSION="1.2.3"' "$FIX/lib/utils.sh" && pass || fail "version left bumped: $(cat "$FIX/lib/utils.sh")"

begin_test "declining the commit reverts every version field, not just the first"
! grep -rq '1\.2\.4' "$FIX/tools/supercharger.sh" "$FIX/README.md" \
    "$FIX/.claude-plugin/plugin.json" "$FIX/.claude-plugin/marketplace.json" \
  && pass || fail "a sibling version field kept the bump"

begin_test "declining the commit removes the CHANGELOG entry"
! grep -q '1\.2\.4' "$FIX/CHANGELOG.md" && pass || fail "CHANGELOG entry left behind"

begin_test "declining the commit leaves nothing staged"
[ -z "$(git -C "$FIX" diff --cached --name-only)" ] && pass || fail "files left staged"

begin_test "declining the commit creates no commit and no tag"
[ "$(git -C "$FIX" rev-list --count HEAD)" = "1" ] && [ -z "$(git -C "$FIX" tag -l)" ] \
  && pass || fail "a commit or tag was created on the abort path"

# The point of all of the above: a SECOND run must still target v+1, not v+2.
begin_test "a re-run after declining still targets the SAME version"
OUT=$(printf 'n\n' | bash "$FIX/tools/release.sh" patch -m "test" 2>&1 || true)
printf '%s' "$OUT" | grep -q '1\.2\.4' && ! printf '%s' "$OUT" | grep -q '1\.2\.5' \
  && pass || fail "re-run skipped a version (the shipped-wrong-content bug): $(printf '%s' "$OUT" | head -3)"
rm -rf "$FIX"

# --- the snapshot must not clobber pre-existing uncommitted edits ---
begin_test "an uncommitted edit made BEFORE the release survives the abort"
FIX=$(make_fixture)
printf '# Changelog\n\nMY UNCOMMITTED NOTE\n\n- [1.2.3] - 2020-01-01 — previous.\n' > "$FIX/CHANGELOG.md"
printf 'y\nn\n' | bash "$FIX/tools/release.sh" patch -m "test" >/dev/null 2>&1 || true
grep -q 'MY UNCOMMITTED NOTE' "$FIX/CHANGELOG.md" \
  && pass || fail "rollback destroyed a pre-existing uncommitted edit"
rm -rf "$FIX"

# --- --yes drives it without a tty ---
begin_test "--yes completes a release with NO stdin"
FIX=$(make_fixture)
bash "$FIX/tools/release.sh" patch -m "test" --yes < /dev/null >/dev/null 2>&1 || true
[ "$(git -C "$FIX" tag -l)" = "v1.2.4" ] && pass || fail "--yes did not reach the tag (got: '$(git -C "$FIX" tag -l)')"

begin_test "--yes commits the bumped version"
grep -q 'VERSION="1.2.4"' "$FIX/lib/utils.sh" && pass || fail "version not bumped under --yes"

begin_test "--yes tags the commit it just made, not an earlier one"
[ "$(git -C "$FIX" rev-parse v1.2.4)" = "$(git -C "$FIX" rev-parse HEAD)" ] \
  && pass || fail "tag does not point at HEAD"
rm -rf "$FIX"

begin_test "-y and --non-interactive are accepted spellings"
FIX=$(make_fixture)
bash "$FIX/tools/release.sh" patch -m "t" -y < /dev/null >/dev/null 2>&1 || true
A=$(git -C "$FIX" tag -l); rm -rf "$FIX"
FIX=$(make_fixture)
bash "$FIX/tools/release.sh" patch -m "t" --non-interactive < /dev/null >/dev/null 2>&1 || true
B=$(git -C "$FIX" tag -l); rm -rf "$FIX"
[ "$A" = "v1.2.4" ] && [ "$B" = "v1.2.4" ] && pass || fail "alias rejected (-y:'$A' --non-interactive:'$B')"

# --- without --yes, an unanswered prompt must not release ---
begin_test "no --yes and no stdin does NOT release"
FIX=$(make_fixture)
bash "$FIX/tools/release.sh" patch -m "test" < /dev/null >/dev/null 2>&1 || true
[ -z "$(git -C "$FIX" tag -l)" ] && grep -q 'VERSION="1.2.3"' "$FIX/lib/utils.sh" \
  && pass || fail "released without an answer"
rm -rf "$FIX"

# --- v2.29.26: the gate runs against a CLEAN checkout of the candidate tree ---
# KNOWN-ISSUES #2. The suite runs before the commit, so the tree always carried the
# release's own uncommitted changes when tests executed -- conditions that match
# neither CI nor a fresh clone. This fixture's suite FAILS if the tree it runs in is
# dirty, and also requires an UNTRACKED candidate file to be present: together they
# prove the gate sees a clean checkout that still contains everything about to be
# committed (release.sh stages with add -A, so untracked files are part of the release).
FIX=$(make_fixture)
cat > "$FIX/tests/run.sh" <<'RUNEOF'
#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(pwd -P)" != "$(cd "$R" && pwd -P)" ]; then
  echo "SUITE RAN FROM THE WRONG CWD: $(pwd -P) not $R"; echo "Total: 0 passed, 1 failed"; exit 1
fi
if [ -n "$(git -C "$R" status --porcelain 2>/dev/null)" ]; then
  echo "SUITE SAW A DIRTY TREE"; echo "Total: 0 passed, 1 failed"; exit 1
fi
if [ ! -f "$R/candidate-new-file.txt" ]; then
  echo "SUITE MISSING THE UNTRACKED CANDIDATE FILE"; echo "Total: 0 passed, 1 failed"; exit 1
fi
echo "Total: 42 passed, 0 failed"; exit 0
RUNEOF
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -qm "gate fixture" >/dev/null 2>&1
# Now dirty the tree exactly as a real release does: a tracked edit plus a new file.
printf 'version-1.2.3-blue tests-10%%20passing\nlocal edit\n' > "$FIX/README.md"
printf 'new hook shipped in this release\n' > "$FIX/candidate-new-file.txt"
OUT=$(printf 'y\ny\n' | bash "$FIX/tools/release.sh" patch -m "clean gate" 2>&1) || true

begin_test "release gate runs the suite against a clean checkout, not the dirty tree"
if printf '%s' "$OUT" | grep -q 'SUITE SAW A DIRTY TREE'; then
  fail "the gate still ran in the dirty working tree"
elif printf '%s' "$OUT" | grep -q 'SUITE MISSING THE UNTRACKED CANDIDATE FILE'; then
  fail "the clean checkout dropped an untracked file that is part of the release"
else
  grep -q 'VERSION="1.2.4"' "$FIX/lib/utils.sh" && pass \
    || fail "release did not complete; output: $(printf '%s' "$OUT" | tail -5)"
fi

begin_test "the CHANGELOG test count comes from the clean run"
grep -q '42 tests passing' "$FIX/CHANGELOG.md" && pass \
  || fail "expected the clean-run count in CHANGELOG: $(grep -m1 '1.2.4' "$FIX/CHANGELOG.md")"

begin_test "the gate worktree is removed after the release"
_LEFT=$(git -C "$FIX" worktree list 2>/dev/null | wc -l | tr -d ' ')
[ "${_LEFT:-0}" -eq 1 ] && pass || fail "expected only the main worktree, got $_LEFT: $(git -C "$FIX" worktree list)"

report
