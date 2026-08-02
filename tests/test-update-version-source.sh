#!/usr/bin/env bash
# update.sh must compare the INSTALLED version against the repo, not the repo
# against itself (v2.26.25)
#
# `OLD_VERSION="$VERSION"` took the version from the repo's lib/utils.sh, sourced
# a few lines earlier. NEW_VERSION re-sourced that same file after `git pull`, so
# the equality test that decides whether to deploy compared one value to itself.
# Whenever the checkout was already current — always true straight after a local
# release — update.sh printed "Already up to date" and exited 0 having copied
# nothing.
#
# The failure is invisible from the outside: exit 0, a success message, and a
# stale install. It is why an install sat 15 releases behind while every
# /sc-update reported success, and it hid a live security fix that had already
# been committed, tagged and pushed.
#
# Asserted on the real line lifted out of update.sh, not on a copy.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

UPDATE="$REPO_DIR/tools/update.sh"

echo "=== update.sh Version-Source Tests ==="

begin_test "update.sh does not take OLD_VERSION straight from the repo VERSION"
grep -qE '^OLD_VERSION="\$VERSION"' "$UPDATE" \
  && fail "OLD_VERSION reads the repo version — the comparison is repo-vs-repo again" || pass

begin_test "update.sh reads the installed version marker"
grep -q 'OLD_VERSION=.*INSTALLED_VERSION_FILE' "$UPDATE" && pass \
  || fail "OLD_VERSION is not sourced from INSTALLED_VERSION_FILE"

# Behavioural: run the real assignment with a stale marker and a newer repo.
# Comment lines must be dropped by matching the "NNN:<spaces>#" shape that
# grep -n produces — a bare '^\s*#' never matches once the line number is
# prefixed, and the explanatory comment above the fix quotes the old assignment
# verbatim, so a sloppy filter picks the buggy line back up. Nor can 'echo' be
# filtered out: the real assignment uses it for the fallback.
ASSIGN=$(grep -n 'OLD_VERSION=' "$UPDATE" | grep -v '^[0-9]*:[[:space:]]*#' | cut -d: -f2-)

begin_test "the OLD_VERSION assignment was located"
printf '%s' "$ASSIGN" | grep -q 'OLD_VERSION' && pass || fail "could not extract the assignment"

run_assign() { # marker-contents ("" = no file), repo-version -> prints OLD_VERSION
  local marker="$1" repover="$2" td script out
  td=$(mktemp -d); script="$td/run.sh"
  {
    printf 'VERSION=%q\n' "$repover"
    printf 'INSTALLED_VERSION_FILE=%q\n' "$td/.version"
    printf '%s\n' "$ASSIGN"
    printf 'printf "%%s" "$OLD_VERSION"\n'
  } > "$script"
  [ -n "$marker" ] && printf '%s\n' "$marker" > "$td/.version"
  out=$(bash "$script" 2>/dev/null)
  rm -rf "$td"
  printf '%s' "$out"
}

begin_test "a stale install reports the INSTALLED version, not the repo's"
GOT=$(run_assign "2.26.1" "2.26.25")
[ "$GOT" = "2.26.1" ] && pass || fail "expected 2.26.1 (installed), got '$GOT' — update would skip the deploy"

begin_test "an up-to-date install compares equal (no needless redeploy)"
GOT=$(run_assign "2.26.25" "2.26.25")
[ "$GOT" = "2.26.25" ] && pass || fail "expected 2.26.25, got '$GOT'"

begin_test "no installed marker falls back to the repo version"
GOT=$(run_assign "" "2.26.25")
[ "$GOT" = "2.26.25" ] && pass || fail "expected the repo version as fallback, got '$GOT'"

begin_test "an empty marker file falls back rather than yielding an empty version"
GOT=$(run_assign " " "2.26.25")
[ -n "$GOT" ] && pass || fail "empty marker produced an empty OLD_VERSION"

# The guard this whole test exists to protect: stale install must not compare
# equal to the repo, because equality is what short-circuits the deploy.
begin_test "stale install does NOT compare equal to the repo version"
[ "$(run_assign "2.26.1" "2.26.25")" != "2.26.25" ] && pass \
  || fail "stale install compares equal — 'Already up to date' with nothing deployed"

report
