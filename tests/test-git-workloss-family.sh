#!/usr/bin/env bash
# The rest of the git work-destroying family (v2.26.30)
#
# git-safety already owned "do not destroy uncommitted work" — reset --hard,
# checkout -- ., restore <path>, stash drop|clear, clean -f all blocked. But only
# some ARMS of that rule were covered. These are the siblings that reach the same
# outcome by another spelling, found by testing the live hook during a survey of
# other guardrail projects rather than by reading one:
#
#   force checkout/switch   git checkout -f|--force, git switch -f|--discard-changes
#   ref deletion            git branch -D (non-protected), push --delete, update-ref -d
#   the recovery net        git reflog expire --expire=now, git gc --prune=now
#   history rewrite         filter-branch, filter-repo, replace --graft,
#                           worktree remove --force, rebase --skip
#
# The reflog pair is the point of the whole exercise. `git reset --hard` was
# already blocked, but the reflog is *why* an executed reset --hard is survivable
# — so the commands that delete the reflog were the ones making the damage
# permanent, and they were unguarded. Guarding an action while leaving its undo
# unguarded is the gap this closes.
#
# Severity split, deliberately: BLOCK only where there is no routine use, ASK
# where a real workflow exists (deleting a merged branch, rewriting history to
# strip a leaked secret). Denying those trades one class of lost work for daily
# friction, and friction is what gets a guard layer uninstalled.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GS="$REPO_DIR/hooks/git-safety.sh"

verdict() { # command -> BLOCK | ASK | allow
  local j out rc
  j=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1")
  out=$(printf '%s' "$j" | bash "$GS" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo BLOCK
  elif printf '%s' "$out" | grep -q '"ask"'; then echo ASK
  else echo allow; fi
}

expect() { # command, expected
  begin_test "$2: $1"
  local got; got=$(verdict "$1")
  [ "$got" = "$2" ] && pass || fail "expected $2, got $got"
}

echo "=== git Work-Loss Family Tests ==="

# --- hard block: no routine use ---------------------------------------------
expect 'git checkout -f main'                        BLOCK
expect 'git checkout --force main'                   BLOCK
expect 'git switch -f main'                          BLOCK
expect 'git switch --discard-changes main'           BLOCK
expect 'git update-ref -d refs/heads/x'              BLOCK

# The recovery net. Both spellings.
expect 'git reflog expire --expire=now --all'        BLOCK
expect 'git reflog expire --expire-unreachable=now'  BLOCK

# Already-protected branch stays a hard block, not downgraded to ask.
expect 'git branch -D main'                          BLOCK
expect 'git branch -D master'                        BLOCK

# --- ask: destructive but with a legitimate workflow ------------------------
expect 'git branch -D feature'                       ASK
expect 'git branch --delete --force feature'         ASK
expect 'git push origin --delete feature'            ASK
expect 'git push origin :feature'                    ASK
expect 'git gc --prune=now'                          ASK
expect 'git filter-branch --force --all'             ASK
expect 'git filter-repo --path secrets --invert-paths' ASK
expect 'git worktree remove --force ../wt'           ASK
expect 'git rebase --skip'                           ASK
expect 'git replace --graft HEAD HEAD~5'             ASK

# --- false positives: everyday git must be untouched ------------------------
# This is the half that decides whether the feature is worth having. The regexes
# above match on flags, and several everyday commands carry confusable ones:
# `checkout -b` vs `-f`, `fetch --prune` vs `gc --prune=`, `push HEAD:main` vs
# `push :branch`, `branch -d` vs `-D`.
for ok in 'git checkout -b feature' 'git checkout main' 'git checkout -- ' \
          'git switch main' 'git switch -c feature' \
          'git branch -d feature' 'git branch -a' 'git branch --list' \
          'git push origin master' 'git push origin HEAD:main' \
          'git push --set-upstream origin feature' \
          'git fetch --prune' 'git gc' 'git gc --auto' \
          'git rebase --continue' 'git rebase -i HEAD~3' 'git rebase main' \
          'git worktree add ../wt' 'git worktree list' \
          'git stash pop' 'git stash list' 'git reflog' 'git reflog show' \
          'git status' 'git log --oneline' 'git diff'; do
  begin_test "not a false positive: $ok"
  got=$(verdict "$ok")
  [ "$got" = "allow" ] && pass || fail "everyday git command got $got"
done

# --- ordering: a hard rule anywhere must beat a soft one recorded earlier ----
# ask() records rather than emits, precisely so an early ask cannot exit the loop
# before a later segment is examined. Without that, the compounds below would
# resolve to ASK and the destructive half would be one keystroke from running.
begin_test "a block in a later segment beats an ask in an earlier one"
[ "$(verdict 'git gc --prune=now && git reflog expire --expire=now --all')" = "BLOCK" ] \
  && pass || fail "early ask short-circuited a later block"

begin_test "block still wins when the ask comes first and differs in kind"
[ "$(verdict 'git branch -D feature && git reset --hard')" = "BLOCK" ] \
  && pass || fail "early ask short-circuited reset --hard"

begin_test "two asks in one command still ask"
[ "$(verdict 'git branch -D feature && git gc --prune=now')" = "ASK" ] \
  && pass || fail "compound of two asks did not ask"

# --- the reason must name the consequence, not just the command -------------
begin_test "the reflog block explains what is lost"
printf '{"tool_name":"Bash","tool_input":{"command":"git reflog expire --expire=now --all"}}' \
  | bash "$GS" 2>&1 | grep -qi 'recover\|safety net' && pass || fail "reason does not state the consequence"

begin_test "the branch -D ask points at the safer flag"
printf '{"tool_name":"Bash","tool_input":{"command":"git branch -D feature"}}' \
  | bash "$GS" 2>&1 | grep -q '\-d' && pass || fail "ask does not offer the narrower alternative"

# --- the fast-path gate must admit every verb the rules match ---------------
# A rule the gate rejects never runs. The gate is matched against raw stdin, so
# each new verb had to be added there too; this pins that they stay in sync.
for verb in switch reflog prune filter-branch filter-repo worktree rebase update-ref; do
  begin_test "fast-path gate admits '$verb'"
  grep -q "$verb" <(sed -n '/^case "\$_INPUT" in/,/^esac/p' "$GS") && pass \
    || fail "gate drops $verb before any rule can see it"
done

report
