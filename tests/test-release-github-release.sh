#!/usr/bin/env bash
# release.sh must publish a GitHub RELEASE, not only a tag (v4.0.28)
#
# For two months it created neither and said nothing: 669 tags, 83 releases, and
# a Releases page whose "Latest" still read v2.26.1 while master moved daily.
# Every step the script DID report was genuinely done, so the run was green and
# the gap was invisible — [[silent-success-tooling]]. GitHub picks Latest from
# release objects and never from tags, so the omission was only ever visible in
# the one place the script does not look.
#
# The static assertions below are the cheap half. The behavioural one matters
# more: the failure path must be LOUD. At that point the tag is already pushed,
# so the code IS released and only the page is missing — an oracle that returns
# quietly there reads as "verified". [[guard-fails-open-oracle-fails-loud]]
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

RELEASE="$REPO_DIR/tools/release.sh"

echo "=== release.sh GitHub-Release Tests ==="

begin_test "release.sh creates a GitHub release object"
grep -q 'gh release create "v\${NEW}"' "$RELEASE" && pass \
  || fail "no gh release create — the Releases page will drift again"

begin_test "the release body is generated, not hand-authored"
grep -q -- '--generate-notes' "$RELEASE" && pass \
  || fail "notes are not generated; a manual step is a step that stops happening"

begin_test "publishing is gated on master"
# Off master the tag points at a commit master does not contain (the v2.26.25
# bug this script already carries a comment about). A release object there is
# the same defect somewhere far more public.
grep -A2 'if \[ "\$BRANCH" = "master" \]; then' "$RELEASE" \
  | grep -q 'publish_github_release' && pass \
  || fail "publish is not inside the master branch"

begin_test "the result is verified by reading it back, not by exit code"
grep -q 'gh release view "v\${NEW}"' "$RELEASE" && pass \
  || fail "no read-back — this script has shipped a green Released before"

begin_test "the dry run says a release would be published"
grep -q 'dry-run\].*publish a GitHub release' "$RELEASE" && pass \
  || fail "dry run understates what a real run does"

# --- behavioural: the failure path must be loud ------------------------------
# Run the function alone, with no `gh` on PATH. Extracting it keeps the rest of
# release.sh (which commits, tags and pushes) from running.
begin_test "a missing gh reports loudly and returns non-zero"
_RGR_TD=$(mktemp -d)
sed -n '/^publish_github_release() {/,/^}/p' "$RELEASE" > "$_RGR_TD/fn.sh"
{
  echo 'YELLOW=""; GREEN=""; NC=""; BOLD=""; NEW="9.9.9"; MESSAGE="subject"'
  cat "$_RGR_TD/fn.sh"
  echo 'publish_github_release; echo "rc=$?"'
} > "$_RGR_TD/probe.sh"
# An EMPTY bin dir, not a nonexistent one, and an absolute interpreter: setting
# PATH to a bogus path also hides `bash` itself, and the probe then "fails" for
# a reason that has nothing to do with gh. [[measurement-fixture-defects]]
mkdir -p "$_RGR_TD/emptybin"
_RGR_OUT=$(PATH="$_RGR_TD/emptybin" "${BASH:-/bin/bash}" "$_RGR_TD/probe.sh" 2>&1)
case "$_RGR_OUT" in
  *"rc=1"*) case "$_RGR_OUT" in
              *gh*) pass ;;
              *) fail "returned 1 but said nothing about gh: $_RGR_OUT" ;;
            esac ;;
  *) fail "expected rc=1 with no gh on PATH, got: $_RGR_OUT" ;;
esac

# The function must not be able to pass when it never reached gh at all — a
# guard that cannot fail is worse than no guard.
begin_test "the extraction actually produced the function (guard the guard)"
grep -q 'gh release create' "$_RGR_TD/fn.sh" && pass \
  || fail "sed extracted the wrong block; the probe above proved nothing"
rm -rf "$_RGR_TD"

report
