#!/usr/bin/env bash
# release.sh stage/promote subcommands: argument routing, per-file counter,
# FF-only guard, and CI gate (via mocked gh).
#
# These tests drive the REAL script against throwaway git repos and mock gh
# shims — a mocked release.sh would not catch the ordering bugs these cover.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== release.sh stage/promote Tests ==="

# ── Fixture builders ──────────────────────────────────────────────────────────

# make_fixture [extra_tests_content] -> prints local_dir
# Creates a minimal repo wired to a bare "origin", with passing tests.
make_fixture() {
  local extra_test="${1:-}"
  local local_dir origin_dir
  local_dir=$(mktemp -d)
  origin_dir=$(mktemp -d)

  git init --bare -q "$origin_dir/origin.git"

  git -C "$local_dir" init -q
  # Force branch to 'master' regardless of git's init.defaultBranch config
  # (newer git versions default to 'main'; stage explicitly requires 'master').
  git -C "$local_dir" symbolic-ref HEAD refs/heads/master
  git -C "$local_dir" config user.email t@t.t
  git -C "$local_dir" config user.name t
  git -C "$local_dir" remote add origin "$origin_dir/origin.git"

  mkdir -p "$local_dir/lib" "$local_dir/tools" "$local_dir/tests" \
            "$local_dir/.claude-plugin"
  printf 'VERSION="1.2.3"\n'                        > "$local_dir/lib/utils.sh"
  printf 'VERSION="1.2.3"\n'                        > "$local_dir/tools/supercharger.sh"
  printf 'version-1.2.3-blue tests-10%%20passing\n' > "$local_dir/README.md"
  printf '# Changelog\n\n- [1.2.3] - 2020-01-01 — previous.\n' \
                                                     > "$local_dir/CHANGELOG.md"
  printf '{"version": "1.2.3"}\n'                   > "$local_dir/.claude-plugin/plugin.json"
  printf '{"version": "1.2.3"}\n'                   > "$local_dir/.claude-plugin/marketplace.json"
  # Passing smoke test — matches the pattern tests/test-*.sh
  printf '#!/usr/bin/env bash\necho "  PASS test1"\necho ""\necho "5 passed, 0 failed (5 total)"\n' \
                                                     > "$local_dir/tests/test-smoke.sh"
  if [ -n "$extra_test" ]; then
    printf '%s' "$extra_test" > "$local_dir/tests/test-extra.sh"
  fi
  cp "$REPO_DIR/tools/release.sh" "$local_dir/tools/release.sh"

  git -C "$local_dir" add -A >/dev/null 2>&1
  git -C "$local_dir" commit -qm "init" >/dev/null 2>&1
  # Push as 'master' (works for both git versions).
  git -C "$local_dir" push -u origin HEAD:master -q >/dev/null 2>&1
  git -C "$local_dir" tag "v1.2.3" >/dev/null 2>&1
  git -C "$local_dir" push origin "v1.2.3" -q >/dev/null 2>&1

  printf '%s' "$local_dir"
}

# make_gh_mock <dir> <status> <conclusion> <jobs_conclusion> <branch_sha>
# Creates a fake 'gh' binary that returns canned JSON for run-list + run-view.
make_gh_mock() {
  local dir="$1" status="$2" conclusion="$3" jobs_ok="$4" sha="$5"
  mkdir -p "$dir"
  # Use /bin/sh shebang — PATH is replaced in tests so 'bash' would recurse.
  cat > "$dir/gh" << MOCKEOF
#!/bin/sh
# Canned gh mock for release.sh promote tests.
_args="\$*"
case "\$_args" in
  *"auth status"*)
    exit 0
    ;;
  *"run list"*)
    printf '[{"headSha":"%s","status":"%s","conclusion":"%s","databaseId":99999,"url":"https://example.com/runs/99999"}]\n' \
      "$sha" "$status" "$conclusion"
    ;;
  *"run view"*"--json jobs"*)
    if [ "$jobs_ok" = "success" ]; then
      printf '{"jobs":[{"name":"Test suite (ubuntu-latest)","conclusion":"success","status":"completed"},{"name":"Test suite (macos-latest)","conclusion":"success","status":"completed"},{"name":"Windows (Git Bash)","conclusion":"success","status":"completed"},{"name":"Shellcheck","conclusion":"success","status":"completed"}]}\n'
    else
      printf '{"jobs":[{"name":"Test suite (ubuntu-latest)","conclusion":"failure","status":"completed"},{"name":"Windows (Git Bash)","conclusion":"failure","status":"completed"}]}\n'
    fi
    ;;
  *"release create"*)
    exit 0
    ;;
  *"release view"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$dir/gh"
}

# ── 1. Argument routing ───────────────────────────────────────────────────────

begin_test "unknown subcommand falls through to legacy path (not stage/promote)"
FIX=$(make_fixture)
# Pass a totally unrecognised first arg — it should hit the arg loop and fail
# with "Unknown argument", NOT trigger stage/promote logic.
OUT=$(bash "$FIX/tools/release.sh" notasubcommand 2>&1 || true)
printf '%s' "$OUT" | grep -q 'Unknown argument' && pass \
  || fail "expected 'Unknown argument', got: $(printf '%s' "$OUT" | head -3)"
rm -rf "$FIX"

begin_test "promote without version prints usage and exits non-zero"
FIX=$(make_fixture)
OUT=$(bash "$FIX/tools/release.sh" promote 2>&1 || true)
printf '%s' "$OUT" | grep -q 'Usage.*promote' && pass \
  || fail "expected usage message, got: $(printf '%s' "$OUT" | head -3)"
rm -rf "$FIX"

begin_test "stage from non-master branch exits with an error"
FIX=$(make_fixture)
git -C "$FIX" checkout -b "feature/x" -q >/dev/null 2>&1
OUT=$(printf 'n\n' | bash "$FIX/tools/release.sh" stage patch -m "t" 2>&1 || true)
printf '%s' "$OUT" | grep -q "must be run from master" && pass \
  || fail "expected 'must be run from master', got: $(printf '%s' "$OUT" | head -3)"
rm -rf "$FIX"

begin_test "legacy path: no subcommand arg shows legacy note on stderr"
FIX=$(make_fixture)
# Pipe 'n' so it aborts at the first confirm without actually releasing.
OUT=$(printf 'n\n' | bash "$FIX/tools/release.sh" patch -m "t" 2>&1 || true)
printf '%s' "$OUT" | grep -q "stage" && pass \
  || fail "expected stage/promote note in legacy path output: $(printf '%s' "$OUT" | head -3)"
rm -rf "$FIX"

# ── 2. Per-file counter ───────────────────────────────────────────────────────

begin_test "stage sums passing counts from multiple test files"
PASSING_TEST='#!/usr/bin/env bash
echo "  PASS one"
echo ""
echo "3 passed, 0 failed (3 total)"
'
FIX=$(make_fixture "$PASSING_TEST")
PRE_STAGE_SHA=$(git -C "$FIX" rev-parse master)
OUT=$(printf 'y\ny\n' | bash "$FIX/tools/release.sh" stage patch -m "test" 2>&1 || true)
# test-smoke.sh has 5, test-extra.sh has 3 → expect 8 in CHANGELOG
printf '%s' "$OUT" | grep -q '8 tests passing' && pass \
  || fail "expected '8 tests passing' (5+3) in CHANGELOG line: $(printf '%s' "$OUT" | grep 'tests passing' || echo '<not found>')"

begin_test "a message ending in a period does not double up in the CHANGELOG line"
# The line template is "— ${MESSAGE}. ${N} tests passing.", so a message written
# as a sentence produced "…exemption.. 5761 tests passing." — v4.1.7's own entry.
# Own fixture in its own variable: the NEXT test reuses $FIX and $PRE_STAGE_SHA
# from the per-file counter test above, so reassigning either here breaks it.
DOT_FIX=$(make_fixture)
DOT_OUT=$(printf 'y\ny\n' | bash "$DOT_FIX/tools/release.sh" stage patch -m "fixed the thing." 2>&1 || true)
DOT_LINE=$(printf '%s' "$DOT_OUT" | grep 'tests passing' | head -1)
printf '%s' "$DOT_LINE" | grep -q '\.\.' \
  && fail "double period in CHANGELOG line: $DOT_LINE" || pass
rm -rf "$DOT_FIX"

begin_test "stage does NOT advance master — release commit is only on rel/ branch"
# The critical invariant: master must stay at its pre-stage HEAD after stage.
# The old buggy code committed on master first, then created rel/ from it —
# git checkout master at the end returned to the same (advanced) master.
POST_STAGE_MASTER=$(git -C "$FIX" rev-parse master 2>/dev/null || echo "missing")
[ "$POST_STAGE_MASTER" = "$PRE_STAGE_SHA" ] && pass \
  || fail "master was advanced: was $PRE_STAGE_SHA, now $POST_STAGE_MASTER"

begin_test "stage commit exists on rel/ branch, not master"
REL_SHA=$(git -C "$FIX" rev-parse "rel/1.2.4" 2>/dev/null || echo "no-branch")
[ "$REL_SHA" != "no-branch" ] && [ "$REL_SHA" != "$PRE_STAGE_SHA" ] && pass \
  || fail "expected rel/1.2.4 to point at the release commit (not master HEAD)"
rm -rf "$FIX"

begin_test "stage aborts when a test file has failures"
FAILING_TEST='#!/usr/bin/env bash
echo "  FAIL bad"
echo ""
echo "0 passed, 1 failed (1 total)"
'
FIX=$(make_fixture "$FAILING_TEST")
OUT=$(printf 'y\ny\n' | bash "$FIX/tools/release.sh" stage patch -m "test" 2>&1 || true)
printf '%s' "$OUT" | grep -q 'Smoke gate\|Fix failing' && pass \
  || fail "expected abort message on failing test: $(printf '%s' "$OUT" | head -5)"
# Version must not have been bumped
grep -q 'VERSION="1.2.3"' "$FIX/lib/utils.sh" && true \
  || fail "version was bumped despite test failure"
rm -rf "$FIX"

begin_test "stage aborts when a test file has failures — version not bumped"
FAILING_TEST2='#!/usr/bin/env bash
echo "2 passed, 2 failed (4 total)"
'
FIX=$(make_fixture "$FAILING_TEST2")
printf 'y\ny\n' | bash "$FIX/tools/release.sh" stage patch -m "test" >/dev/null 2>&1 || true
grep -q 'VERSION="1.2.3"' "$FIX/lib/utils.sh" && pass \
  || fail "version was bumped despite failing smoke gate"
rm -rf "$FIX"

begin_test "stage aborts when a test file CRASHES without a report line"
# Exits non-zero and prints no "N passed/failed" line — the smoke gate must not
# count it as 0/0 and pass; it must flag the crash and abort (version unbumped).
CRASH_TEST='#!/usr/bin/env bash
echo "harness died before reporting"
exit 3
'
FIX=$(make_fixture "$CRASH_TEST")
OUT=$(printf 'y\ny\n' | bash "$FIX/tools/release.sh" stage patch -m "test" 2>&1 || true)
printf '%s' "$OUT" | grep -q 'crashed\|Smoke gate\|Fix failing' \
  && grep -q 'VERSION="1.2.3"' "$FIX/lib/utils.sh" && pass \
  || fail "crashing test file did not abort the stage: $(printf '%s' "$OUT" | tail -5)"
rm -rf "$FIX"

# ── 3. FF-only guard ─────────────────────────────────────────────────────────

# Build a fixture where origin/rel/X.Y.Z has diverged from master:
# master: A → B (extra commit not in rel)
# rel:    A → C (bumped differently)
# promote --ff-only must refuse.
begin_test "promote refuses when master has diverged from rel branch"
FIX=$(make_fixture)
ORIGIN_GIT="$FIX/../origin.git"
# Determine where origin is by reading the remote URL
ORIGIN_URL=$(git -C "$FIX" remote get-url origin 2>/dev/null || echo "")

# Create rel/1.2.4 on a divergent history by creating it from the initial commit,
# then adding an extra commit to master.
git -C "$FIX" checkout -b "rel/1.2.4" -q >/dev/null 2>&1
printf 'VERSION="1.2.4"\n' > "$FIX/lib/utils.sh"
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -qm "chore: release v1.2.4" >/dev/null 2>&1
git -C "$FIX" push -u origin "rel/1.2.4" -q >/dev/null 2>&1

# Add a commit to master that rel/1.2.4 does NOT contain.
git -C "$FIX" checkout master -q >/dev/null 2>&1
printf 'extra line\n' >> "$FIX/README.md"
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -qm "extra master commit" >/dev/null 2>&1
git -C "$FIX" push origin master -q >/dev/null 2>&1

# Create a mock gh that says CI is all-green.
MOCK_DIR=$(mktemp -d)
REL_SHA=$(git -C "$FIX" rev-parse "origin/rel/1.2.4" 2>/dev/null || echo "deadbeef")
make_gh_mock "$MOCK_DIR" "completed" "success" "success" "$REL_SHA"

# promote exits before reaching the confirm prompt (at FF check), so --yes
# is used here and PATH is set for the bash invocation, not the printf.
OUT=$(PATH="$MOCK_DIR:$PATH" bash "$FIX/tools/release.sh" promote 1.2.4 --yes 2>&1 || true)
printf '%s' "$OUT" | grep -qi 'diverged\|fast-forward\|cannot' && pass \
  || fail "expected FF-refused message, got: $(printf '%s' "$OUT" | head -5)"
rm -rf "$FIX" "$MOCK_DIR"

# ── 4. CI gate ────────────────────────────────────────────────────────────────

# Helper: build a fixture with rel/1.2.4 already on origin (FF-able from master).
make_promote_fixture() {
  local local_dir
  local_dir=$(make_fixture)
  git -C "$local_dir" checkout -b "rel/1.2.4" -q >/dev/null 2>&1
  printf 'VERSION="1.2.4"\n' > "$local_dir/lib/utils.sh"
  git -C "$local_dir" add -A >/dev/null 2>&1
  git -C "$local_dir" commit -qm "chore: release v1.2.4" >/dev/null 2>&1
  git -C "$local_dir" push -u origin "rel/1.2.4" -q >/dev/null 2>&1
  git -C "$local_dir" checkout master -q >/dev/null 2>&1
  printf '%s' "$local_dir"
}

begin_test "declining the commit in stage leaves master at pre-stage HEAD"
# If user says y to Proceed but n to Commit, rollback+cleanup must restore master.
FIX=$(make_fixture)
PRE_SHA=$(git -C "$FIX" rev-parse master)
printf 'y\nn\n' | bash "$FIX/tools/release.sh" stage patch -m "t" >/dev/null 2>&1 || true
# Back on master, same SHA
[ "$(git -C "$FIX" rev-parse master 2>/dev/null || echo x)" = "$PRE_SHA" ] && pass \
  || fail "master moved after commit-decline in stage"
# lib/utils.sh must be reverted
grep -q 'VERSION="1.2.3"' "$FIX/lib/utils.sh" && pass \
  || fail "version still bumped after commit-decline"
rm -rf "$FIX"

begin_test "promote refuses when CI run is still in progress"
FIX=$(make_promote_fixture)
MOCK_DIR=$(mktemp -d)
REL_SHA=$(git -C "$FIX" rev-parse "origin/rel/1.2.4")
make_gh_mock "$MOCK_DIR" "in_progress" "" "success" "$REL_SHA"
OUT=$(PATH="$MOCK_DIR:$PATH" bash "$FIX/tools/release.sh" promote 1.2.4 --yes 2>&1 || true)
printf '%s' "$OUT" | grep -q 'not finished\|in_progress' && pass \
  || fail "expected 'not finished' message, got: $(printf '%s' "$OUT" | head -5)"
# master must not have moved
[ "$(git -C "$FIX" rev-parse master)" != "$(git -C "$FIX" rev-parse origin/rel/1.2.4)" ] \
  && pass || fail "master was advanced despite in-progress CI"
rm -rf "$FIX" "$MOCK_DIR"

begin_test "promote refuses when a CI job failed"
FIX=$(make_promote_fixture)
MOCK_DIR=$(mktemp -d)
REL_SHA=$(git -C "$FIX" rev-parse "origin/rel/1.2.4")
make_gh_mock "$MOCK_DIR" "completed" "failure" "failure" "$REL_SHA"
OUT=$(PATH="$MOCK_DIR:$PATH" bash "$FIX/tools/release.sh" promote 1.2.4 --yes 2>&1 || true)
printf '%s' "$OUT" | grep -q 'CI gate failed\|FAILED' && pass \
  || fail "expected CI gate failure message, got: $(printf '%s' "$OUT" | head -5)"
# master must not have moved
M=$(git -C "$FIX" rev-parse master)
R=$(git -C "$FIX" rev-parse "origin/rel/1.2.4")
[ "$M" != "$R" ] && pass \
  || fail "master was advanced despite CI job failure"
rm -rf "$FIX" "$MOCK_DIR"

begin_test "promote refuses when Windows job is absent from CI results"
FIX=$(make_promote_fixture)
MOCK_DIR=$(mktemp -d)
REL_SHA=$(git -C "$FIX" rev-parse "origin/rel/1.2.4")
# Override the mock to return jobs WITHOUT the Windows job.
cat > "$MOCK_DIR/gh" << 'NOWIN'
#!/bin/sh
_args="$*"
case "$_args" in
  *"auth status"*) exit 0 ;;
  *"run list"*)
    # Use a hardcoded sha — the test fixture's REL_SHA is baked into make_promote_fixture
    # This mock reads the sha argument from run list's branch name instead.
    printf '[{"headSha":"'"$REL_SHA"'","status":"completed","conclusion":"success","databaseId":99999,"url":"https://example.com/runs/99999"}]\n'
    ;;
  *"run view"*"--json jobs"*)
    # Only Linux jobs, no Windows
    printf '{"jobs":[{"name":"Test suite (ubuntu-latest)","conclusion":"success","status":"completed"},{"name":"Shellcheck","conclusion":"success","status":"completed"}]}\n'
    ;;
  *) exit 0 ;;
esac
NOWIN
# REL_SHA needs to be in the script — rewrite it with the real sha.
sed -i.bak "s/\"\$REL_SHA\"/\"$REL_SHA\"/g" "$MOCK_DIR/gh" 2>/dev/null || true
rm -f "$MOCK_DIR/gh.bak"
chmod +x "$MOCK_DIR/gh"
OUT=$(PATH="$MOCK_DIR:$PATH" bash "$FIX/tools/release.sh" promote 1.2.4 --yes 2>&1 || true)
printf '%s' "$OUT" | grep -q 'Windows (Git Bash)' && pass \
  || fail "expected Windows job gate message, got: $(printf '%s' "$OUT" | head -5)"
rm -rf "$FIX" "$MOCK_DIR"

begin_test "promote refuses when origin/rel/X.Y.Z does not exist"
FIX=$(make_fixture)
MOCK_DIR=$(mktemp -d)
# gh mock: doesn't matter, promote should fail before calling gh
make_gh_mock "$MOCK_DIR" "completed" "success" "success" "deadbeef"
OUT=$(PATH="$MOCK_DIR:$PATH" bash "$FIX/tools/release.sh" promote 9.9.9 --yes 2>&1 || true)
printf '%s' "$OUT" | grep -q 'does not exist\|9.9.9' && pass \
  || fail "expected 'does not exist' message, got: $(printf '%s' "$OUT" | head -3)"
rm -rf "$FIX" "$MOCK_DIR"

report
