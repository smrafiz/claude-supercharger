#!/usr/bin/env bash
# Suite for commit-guard.sh's default-branch check (v4.0.18)
#
# The rule existed only in prose — guardrails.md and Claude Code's own operating
# instructions both say to branch first, and nothing enforced it. Measured before
# this check existed: `git commit -m "wip"` on master was allowed by all 160
# hooks. A rule stated in a description with no mechanism is the highest-yield
# hook candidate this project has found.
#
# The restraint half carries more weight than the detection half. This fires on a
# command developers run constantly, so it must be silent on a feature branch,
# silent when it cannot determine the default, and silent after the first ask.
# Measured across three local repos when it was written: two were on feature
# branches (silent), one was on master — this repo, which is trunk-based on
# purpose and therefore needs the documented escape hatch to be real.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/commit-guard.sh"

# A real git repo, optionally with a remote so `symbolic-ref origin/HEAD`
# resolves the way it does in a clone.
_mkrepo() {  # $1 = branch to end on, $2 = default branch, $3 = "noremote" to skip
  local d def; d=$(mktemp -d); def="${2:-main}"
  git -C "$d" init -q -b "$def" 2>/dev/null
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  printf 'x\n' > "$d/f.txt"
  git -C "$d" add f.txt 2>/dev/null
  git -C "$d" commit -q -m init 2>/dev/null
  if [ "${3:-}" != "noremote" ]; then
    local r; r=$(mktemp -d)
    git init -q --bare -b "$def" "$r" 2>/dev/null
    git -C "$d" remote add origin "$r" 2>/dev/null
    git -C "$d" push -q origin "$def" 2>/dev/null
    git -C "$d" remote set-head origin "$def" 2>/dev/null
  fi
  [ "$1" != "$def" ] && git -C "$d" switch -q -c "$1" 2>/dev/null
  printf '%s' "$d"
}

# $1 = repo, $2 = command (default: a plain commit), $3 = shared state dir
_verdict() {
  local repo="$1" cmd="${2:-git commit -m \"wip\"}" st="${3:-$(mktemp -d)}" out
  out=$(printf '{"session_id":"b1","tool_name":"Bash","tool_input":{"command":%s},"cwd":"%s"}' \
        "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" "$repo" \
      | (cd "$repo" && HOME="$st" SUPERCHARGER_STATE="$st" bash "$HOOK" 2>/dev/null))
  case "$out" in
    *'"ask"'*)  printf 'ask' ;;
    *'"deny"'*) printf 'deny' ;;
    *)          printf 'allow' ;;
  esac
}

echo "=== commit-guard: default-branch check ==="

begin_test "default-branch: committing on the default branch asks"
R=$(_mkrepo main); ST=$(mktemp -d)
[ "$(_verdict "$R" "" "$ST")" = ask ] && pass || fail "commit on main was silent"

begin_test "default-branch: it asks ONCE per session per repo"
# A release cuts several commits in a row; re-asking each time is how a guard
# gets switched off.
[ "$(_verdict "$R" "" "$ST")" = allow ] && pass || fail "asked twice in one session"
rm -rf "$R" "$ST"

begin_test "default-branch: a feature branch is silent"
R=$(_mkrepo feat/x)
[ "$(_verdict "$R")" = allow ] && pass || fail "asked while on a feature branch"
rm -rf "$R"

begin_test "default-branch: master as the default also asks"
R=$(_mkrepo master master)
[ "$(_verdict "$R")" = ask ] && pass || fail "only recognised 'main'"
rm -rf "$R"

begin_test "default-branch: a project can opt out"
# Not theoretical — THIS repo is trunk-based and needs it. The agent cannot
# write that file itself (the selfmod guard denies it), which is the point:
# the escape hatch is a human decision.
R=$(_mkrepo main)
printf '{"allowDefaultBranchCommits": true}\n' > "$R/.supercharger.json"
[ "$(_verdict "$R")" = allow ] && pass || fail "opt-out was ignored"
rm -rf "$R"

begin_test "default-branch: the env kill switch is honoured"
R=$(_mkrepo main); ST=$(mktemp -d)
OUT=$(printf '{"session_id":"k","tool_name":"Bash","tool_input":{"command":"git commit -m \\"x\\""},"cwd":"%s"}' "$R" \
  | (cd "$R" && HOME="$ST" SUPERCHARGER_STATE="$ST" SUPERCHARGER_DEFAULT_BRANCH_GUARD=0 bash "$HOOK" 2>/dev/null))
case "$OUT" in *'"ask"'*) fail "kill switch ignored" ;; *) pass ;; esac
rm -rf "$R" "$ST"

begin_test "default-branch: git commit --help is not a commit"
R=$(_mkrepo main)
[ "$(_verdict "$R" "git commit --help")" = allow ] && pass || fail "asked on a help invocation"

begin_test "default-branch: an unrelated git command is silent"
[ "$(_verdict "$R" "git status")" = allow ] && pass || fail "asked on git status"
rm -rf "$R"

begin_test "default-branch: no remote, conventional name, still asks"
R=$(_mkrepo main main noremote)
[ "$(_verdict "$R")" = ask ] && pass || fail "fell back too conservatively"
rm -rf "$R"

begin_test "default-branch: no remote and an unconventional name stays SILENT"
# The restraint that keeps this honest: with no origin/HEAD there is no way to
# know `trunk` is the default, and guessing from the CURRENT branch would make
# every branch its own default and the check vacuous.
R=$(_mkrepo trunk trunk noremote)
[ "$(_verdict "$R")" = allow ] && pass || fail "guessed a default it could not know"
rm -rf "$R"

report
