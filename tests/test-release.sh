#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/release.sh"

echo "=== Release Tool Tests ==="

# All tests use --dry-run on the actual repo (no file modifications)

begin_test "release: --dry-run patch bump shows incremented patch version"
CURRENT=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
EXPECTED="${MAJ}.${MIN}.$((PAT + 1))"
EXIT=0
OUTPUT=$(bash "$TOOL" patch --message "test" --dry-run 2>&1) || EXIT=$?
[ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "$EXPECTED" && pass || fail "expected $EXPECTED in output; exit=$EXIT output: $OUTPUT"

begin_test "release: --dry-run minor bump shows incremented minor version"
CURRENT=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
EXPECTED="${MAJ}.$((MIN + 1)).0"
EXIT=0
OUTPUT=$(bash "$TOOL" minor --message "test" --dry-run 2>&1) || EXIT=$?
[ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "$EXPECTED" && pass || fail "expected $EXPECTED in output; exit=$EXIT"

begin_test "release: --dry-run major bump shows incremented major version"
CURRENT=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
EXPECTED="$((MAJ + 1)).0.0"
EXIT=0
OUTPUT=$(bash "$TOOL" major --message "test" --dry-run 2>&1) || EXIT=$?
# The computed version must appear either way. A clean dry-run exits 0; if that
# version's tag already exists the tool now refuses BEFORE doing any work, which
# is a correct outcome and not a failure of the bump arithmetic. The repo carries
# 53 orphaned v3.x tags, so `major` off a 2.x version legitimately lands here.
if echo "$OUTPUT" | grep -q "$EXPECTED"; then
  if [ "$EXIT" -eq 0 ] || echo "$OUTPUT" | grep -q "already exists"; then pass
  else fail "computed $EXPECTED but exited $EXIT without a collision message"; fi
else fail "expected $EXPECTED in output; exit=$EXIT"; fi

begin_test "release: --dry-run output contains 'dry-run' notice"
EXIT=0
OUTPUT=$(bash "$TOOL" patch --message "test" --dry-run 2>&1) || EXIT=$?
[ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -qi "dry.run" && pass || fail "expected dry-run notice; exit=$EXIT"

begin_test "release: --dry-run does not modify lib/utils.sh"
BEFORE=$(cat "$REPO_DIR/lib/utils.sh")
bash "$TOOL" patch --message "test" --dry-run >/dev/null 2>&1 || true
AFTER=$(cat "$REPO_DIR/lib/utils.sh")
[ "$BEFORE" = "$AFTER" ] && pass || fail "lib/utils.sh was modified"

begin_test "release: unknown argument exits non-zero"
EXIT=0
OUTPUT=$(bash "$TOOL" --unknown-flag 2>&1) || EXIT=$?
[ "$EXIT" -ne 0 ] && pass || fail "expected non-zero exit for unknown arg"

begin_test "release: patch is default bump type"
CURRENT=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
PATCH_VERSION="${MAJ}.${MIN}.$((PAT + 1))"
EXIT=0
OUTPUT=$(bash "$TOOL" --message "test" --dry-run 2>&1) || EXIT=$?
[ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "$PATCH_VERSION" && pass || fail "expected default patch bump to $PATCH_VERSION"

begin_test "release: accepts an explicit X.Y.Z version"
# Needed because the computed bump is not always the version you want: this repo
# has 53 orphaned v3.x tags, so `major` off 2.x computes an already-published
# version and there was no way to say "make it 4.0.0" instead.
EXIT=0
OUTPUT=$(bash "$TOOL" 9.9.9 --message "test" --dry-run 2>&1) || EXIT=$?
[ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "9.9.9" && echo "$OUTPUT" | grep -q "explicit" \
  && pass || fail "explicit version not honoured; exit=$EXIT output: $OUTPUT"

begin_test "release: refuses a version whose tag already exists"
# Tagging is the LAST step, after the ~7-minute suite and after the version bump
# and CHANGELOG entry are written. A collision discovered there leaves a mutated
# tree behind, so the check has to happen before any of that work.
EXISTING=$(git -C "$REPO_DIR" tag | head -1 | sed 's/^v//')
if [ -z "$EXISTING" ]; then pass; else
  EXIT=0
  OUTPUT=$(bash "$TOOL" "$EXISTING" --message "test" --dry-run 2>&1) || EXIT=$?
  [ "$EXIT" -ne 0 ] && echo "$OUTPUT" | grep -q "already exists" \
    && pass || fail "released over existing tag v$EXISTING; exit=$EXIT"
fi

begin_test "release: the collision check runs BEFORE the test suite"
# A guard that fires after the suite has already run is a guard that costs seven
# minutes to tell you something it knew at the start.
EXISTING=$(git -C "$REPO_DIR" tag | head -1 | sed 's/^v//')
if [ -z "$EXISTING" ]; then pass; else
  OUTPUT=$(bash "$TOOL" "$EXISTING" --message "test" --dry-run 2>&1 || true)
  echo "$OUTPUT" | grep -q "Running tests" \
    && fail "suite ran before the collision was detected" || pass
fi

begin_test "release: rejects a malformed explicit version"
EXIT=0
OUTPUT=$(bash "$TOOL" 1.2 --message "test" --dry-run 2>&1) || EXIT=$?
[ "$EXIT" -ne 0 ] && pass || fail "accepted a malformed version: $OUTPUT"

report
