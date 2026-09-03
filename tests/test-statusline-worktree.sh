#!/usr/bin/env bash
# v4.0.23 statusline worktree label.
#
# `dirname` is basename(cwd), and a linked worktree's directory REPLACES the repo
# name there — so the line read `wt-demo | branch`: neither the parent repo nor
# the fact that it was a worktree was visible anywhere. Reported by the user.
#
# The label is derived from --git-common-dir vs --show-toplevel, not from the
# path shape: a directory merely NAMED like a worktree is an ordinary checkout
# and must stay unlabelled, which is what the third test pins.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SL="$REPO_DIR/hooks/statusline.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Statusline Worktree Label Tests ==="

TD=$(mktemp -d)
# The git-fact cache keys on $HOME, not SUPERCHARGER_STATE. Without an isolated
# HOME these tests read (and poison) the developer's live cache — see
# [[test-telemetry-isolation]].
export HOME="$TD/home"; mkdir -p "$HOME/.claude/supercharger/scope"
ST="$TD/state"; mkdir -p "$ST/scope"

git init -q "$TD/myrepo" 2>/dev/null
(
  cd "$TD/myrepo" || exit 1
  git config user.email t@t; git config user.name t
  echo x > f.txt; git add f.txt; git commit -qm init
  git worktree add -q "$TD/feature-wt" -b feature-x
) >/dev/null 2>&1

render() { # cwd -> first line, ANSI stripped
  python3 -c 'import json,sys;print(json.dumps({"model":{"display_name":"M"},"cwd":sys.argv[1],"session_id":"wt-test","transcript_path":"/dev/null","workspace":{"current_dir":sys.argv[1]}}))' "$1" \
    | SUPERCHARGER_STATE="$ST" bash "$SL" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}

begin_test "a linked worktree shows repo/worktree, not just the worktree dir"
OUT=$(render "$TD/feature-wt")
printf '%s' "$OUT" | grep -q 'myrepo/feature-wt' && pass || fail "got: $OUT"

begin_test "and the branch is still there"
printf '%s' "$(render "$TD/feature-wt")" | grep -q 'feature-x' && pass \
  || fail "branch lost: $(render "$TD/feature-wt")"

begin_test "an ordinary checkout is unchanged — bare repo name, no slash"
rm -f "$HOME/.claude/supercharger/scope/".statusline-git-*
OUT=$(render "$TD/myrepo")
{ printf '%s' "$OUT" | grep -q ' myrepo ' \
  && ! printf '%s' "$OUT" | grep -q 'myrepo/'; } && pass || fail "got: $OUT"

begin_test "a subdirectory of a worktree still names the worktree"
mkdir -p "$TD/feature-wt/src"
rm -f "$HOME/.claude/supercharger/scope/".statusline-git-*
printf '%s' "$(render "$TD/feature-wt/src")" | grep -q 'myrepo/feature-wt' && pass \
  || fail "got: $(render "$TD/feature-wt/src")"

begin_test "a non-git directory renders no label and does not error"
OUT=$(render "$TD")
[ -n "$OUT" ] && ! printf '%s' "$OUT" | grep -q '/' && pass || fail "got: $OUT"

# The extra fork is paid on the cache-miss path only; a cached render must not
# lose the label, which is what a missing 'wt' key in the cache would do.
begin_test "the label survives a cached render"
rm -f "$HOME/.claude/supercharger/scope/".statusline-git-*
render "$TD/feature-wt" >/dev/null
printf '%s' "$(render "$TD/feature-wt")" | grep -q 'myrepo/feature-wt' && pass \
  || fail "label dropped when served from cache: $(render "$TD/feature-wt")"

git -C "$TD/myrepo" worktree remove --force "$TD/feature-wt" >/dev/null 2>&1
rm -rf "$TD"
report
