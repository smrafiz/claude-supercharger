#!/usr/bin/env bash
# The installed version string must identify the installed code (v4.1.11)
#
# update.sh installs master HEAD, but VERSION in lib/utils.sh only moves when
# release.sh bumps it. Everything merged between two releases therefore ships
# under the PREVIOUS release's number, and which of those commits you got
# depends only on when you happened to run the updater:
#
#   machine A updated the hour v4.1.10 was tagged -> v4.1.10 == the tag
#   machine B updated two days later              -> v4.1.10 == tag + 2 commits
#
# Both print "v4.1.10". Observed on 2026-09-22: the installed config-scan.sh was
# byte-identical to master HEAD (modulo the shebang rewrite) and 718 bytes away
# from the v4.1.10 tag.
#
# Worse, the post-pull short-circuit compared versions ONLY, so when the pull
# brought commits that did not bump VERSION it exited "Already up to date" —
# leaving the clone advanced and the INSTALL behind. Same root cause as a
# promote not reinstalling locally.
#
# These pin the contract, not the implementation: a commit stamp is written, an
# unknown or differing stamp means work to do, and an unreachable network never
# invents an update nor hides a known one.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Version identifies code ==="

U="$REPO_DIR/tools/update.sh"

begin_test "install.sh stamps the source commit next to the version"
grep -q 'supercharger/\.commit' "$REPO_DIR/install.sh" && pass \
  || fail "install.sh writes no .commit — nothing can say which code is installed"

begin_test "the commit stamp is removed, not left stale, when git is unavailable"
grep -q 'rm -f "\$HOME/.claude/supercharger/.commit"' "$REPO_DIR/install.sh" && pass \
  || fail "a tarball install would inherit the previous install's SHA"

begin_test "update.sh reads a commit stamp"
grep -q 'local_commit()' "$U" && pass || fail "no local_commit()"

begin_test "update.sh can fetch the upstream commit"
grep -q 'fetch_remote_commit()' "$U" && pass || fail "no fetch_remote_commit()"

begin_test "the post-pull short-circuit is no longer version-only"
# Target the guard that EXITS, not any version comparison in the file: the
# display line below it compares versions too and is not the defect.
GUARD=$(grep -B4 'Already up to date' "$U" | head -20)
case "$GUARD" in
  *OLD_COMMIT*) pass ;;
  *) fail "the exit branch is still version-only — a commit-only update is a no-op" ;;
esac

begin_test "an install with no commit stamp is treated as unknown, not as current"
grep -q '\[ -n "\$OLD_COMMIT" \]' "$U" && pass \
  || fail "an unstamped install would be assumed up to date"

begin_test "--check compares commits when the release number matches"
grep -q 'UPSTREAM_SHA=\$(fetch_remote_commit)' "$U" && pass \
  || fail "--check is version-only, so /sc-update stops before the commit check runs"

begin_test "an unreachable GitHub falls back to the version-only answer"
# Both SHAs must be non-empty before an update is announced, or a failed curl
# would report an update on every check.
grep -q '\[ -n "\$INSTALLED_SHA" \] && \[ -n "\$UPSTREAM_SHA" \]' "$U" && pass \
  || fail "empty SHA is not guarded — a network failure would invent an update"

begin_test "fetch_remote_commit yields empty, never garbage, on failure"
BODY=$(sed -n '/^fetch_remote_commit()/,/^}/p' "$U")
if [ -z "$BODY" ]; then
  # Absent function also returns nothing. Without this arm the check passed
  # against the very defect it exists to catch.
  fail "fetch_remote_commit is not defined - an empty result proves nothing"
else
  OUT=$( curl() { return 7; }; eval "$BODY"; fetch_remote_commit )
  [ -z "$OUT" ] && pass || fail "returned non-empty with no network"
fi

# Shipped in v4.1.11 and caught on the first real update: the stamp said
# "cfdc98bf" (git rev-parse --short picks the shortest UNAMBIGUOUS length, >= 7)
# while the API side was hard-cut to 7, so the same commit compared unequal and
# every check reported an update forever. Static greps missed it because each
# side looked correct alone -- only the round-trip shows it.
begin_test "an 8-char local stamp equals the 7-char remote of the same commit"
FN=$(mktemp)
sed -n '/^sc_sha7()/,/^}/p' "$U" > "$FN"
if [ ! -s "$FN" ]; then
  fail "sc_sha7 is not defined - nothing normalises the two spellings"
else
  . "$FN"
  [ "$(sc_sha7 cfdc98bf)" = "$(sc_sha7 cfdc98b)" ] && pass \
    || fail "same commit still compares unequal across abbreviation lengths"
fi
rm -f "$FN"

begin_test "the stamp is a full SHA, not a variable-length abbreviation"
if grep -q 'rev-parse HEAD' "$REPO_DIR/install.sh" \
   && ! grep -q 'rev-parse --short HEAD' "$REPO_DIR/install.sh"; then
  pass
else
  fail "install.sh still writes an abbreviation whose length can drift"
fi

begin_test "no comparison uses a raw, unnormalised SHA"
if grep -qE '\[ "\$(INSTALLED_SHA|OLD_COMMIT)" (!=|==) "\$(UPSTREAM_SHA|NEW_COMMIT)" \]' "$U"; then
  fail "a raw SHA comparison remains - it will break on an abbreviation change"
else
  pass
fi

begin_test "both scripts still parse"
bash -n "$U" 2>/dev/null && bash -n "$REPO_DIR/install.sh" 2>/dev/null && pass || fail "syntax error"

report
