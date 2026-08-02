#!/usr/bin/env bash
# release.sh must push the branch it committed to, not a hardcoded one (v2.26.25)
#
# The push was `git push origin master`, unconditionally. Releases here are cut
# on a release/X branch and merged to master afterwards, so that line pushed a
# branch the release commit was not on. git printed "Everything up-to-date" and
# exited 0 — a successful no-op — while `push origin vX.Y.Z` on the next line
# happily published a tag pointing at a commit no remote branch contained.
#
# Exit codes cannot see this: every command succeeded. So the assertions below
# use a real repo with a real (bare) remote and check what actually arrived.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

RELEASE="$REPO_DIR/tools/release.sh"

echo "=== release.sh Push-Target Tests ==="

begin_test "release.sh does not push a hardcoded master"
grep -qE '^git -C "\$REPO_DIR" push origin master[[:space:]]*$' "$RELEASE" \
  && fail "push origin master is back — a branch release pushes nothing" || pass

begin_test "release.sh pushes the checked-out branch"
grep -q 'push origin "\$BRANCH"' "$RELEASE" && pass || fail "push target is not \$BRANCH"

begin_test "release.sh resolves BRANCH from HEAD"
grep -q 'BRANCH=\$(git -C "\$REPO_DIR" rev-parse --abbrev-ref HEAD)' "$RELEASE" \
  && pass || fail "BRANCH is not derived from HEAD"

# --- behavioural: a real commit, a real remote, both branch shapes -----------
# Mirrors the two lines from release.sh rather than invoking the whole script,
# which runs the full suite and prompts twice.
setup_repo() { # -> prints workdir
  local wd
  wd=$(mktemp -d)
  git init -q --bare "$wd/remote.git"
  git init -q "$wd/work"
  git -C "$wd/work" config user.email t@example.com
  git -C "$wd/work" config user.name t
  git -C "$wd/work" remote add origin "$wd/remote.git"
  printf 'v1\n' > "$wd/work/f.txt"
  git -C "$wd/work" add f.txt
  git -C "$wd/work" commit -q -m init
  git -C "$wd/work" branch -M master
  git -C "$wd/work" push -q origin master
  printf '%s' "$wd"
}

# The old line, verbatim, and the new one — run against the same setup so the
# difference in outcome is the code under test and nothing else.
release_push() { # workdir, mode(old|new) -> pushes a release commit + tag
  local wd="$1" mode="$2"
  git -C "$wd/work" checkout -q -b release/9.9.9
  printf 'v2\n' > "$wd/work/f.txt"
  git -C "$wd/work" commit -q -am "chore: release v9.9.9"
  git -C "$wd/work" tag v9.9.9
  if [ "$mode" = "old" ]; then
    git -C "$wd/work" push -q origin master 2>/dev/null || true
  else
    local br
    br=$(git -C "$wd/work" rev-parse --abbrev-ref HEAD)
    git -C "$wd/work" push -q origin "$br" 2>/dev/null || true
  fi
  git -C "$wd/work" push -q origin v9.9.9 2>/dev/null || true
}

# Is the tagged commit reachable from any branch on the remote?
tag_is_orphaned() { # workdir -> 0 if the tag points outside every remote branch
  local wd sha
  wd="$1"
  sha=$(git -C "$wd/work" rev-parse v9.9.9^{commit})
  [ -z "$(git -C "$wd/remote.git" branch --contains "$sha" 2>/dev/null)" ]
}

begin_test "the OLD form publishes a tag no remote branch contains"
WD=$(setup_repo); release_push "$WD" old
tag_is_orphaned "$WD" && pass || fail "expected the old form to orphan the tag — setup is not reproducing the bug"
rm -rf "$WD"

begin_test "the NEW form pushes the branch, so the tag is reachable"
WD=$(setup_repo); release_push "$WD" new
tag_is_orphaned "$WD" && fail "tag still unreachable — the branch was not pushed" || pass
rm -rf "$WD"

begin_test "the NEW form actually creates the branch on the remote"
WD=$(setup_repo); release_push "$WD" new
git -C "$WD/remote.git" rev-parse --verify -q release/9.9.9 >/dev/null \
  && pass || fail "release branch missing from the remote"
rm -rf "$WD"

begin_test "releasing from master still pushes master"
WD=$(setup_repo)
printf 'v2\n' > "$WD/work/f.txt"
git -C "$WD/work" commit -q -am "chore: release v9.9.9"
BR=$(git -C "$WD/work" rev-parse --abbrev-ref HEAD)
git -C "$WD/work" push -q origin "$BR"
[ "$(git -C "$WD/remote.git" rev-parse master)" = "$(git -C "$WD/work" rev-parse master)" ] \
  && pass || fail "master was not pushed"
rm -rf "$WD"

# --- the message must not claim a finished release from a branch ------------
begin_test "a branch release is reported as NOT yet on master"
grep -q 'NOT yet on master' "$RELEASE" && pass || fail "no warning for a branch release"

begin_test "the unconditional 'Released' banner is gated on master"
awk '/^if \[ "\$BRANCH" = "master" \]/,/^fi$/' "$RELEASE" | grep -q 'Released v' \
  && pass || fail "the Released banner is not gated on the branch"

report
