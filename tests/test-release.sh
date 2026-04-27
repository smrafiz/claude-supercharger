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
[ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "$EXPECTED" && pass || fail "expected $EXPECTED in output; exit=$EXIT"

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

report
