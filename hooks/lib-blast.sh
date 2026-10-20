#!/usr/bin/env bash
# Claude Supercharger — blast-radius summary for confirmation prompts
#
# A permission prompt shows the command, not what it does. `blast_summary <cmd>`
# sets BLAST to one line on the effect of a git push or a recursive rm, measured in
# the current directory, or to "" when it has nothing certain to say. sc_decision
# appends it to every ASK, so the prompts our guards already raise say what they
# touch; no new prompt is ever added (the "ask" reason is the only decision text
# Claude Code shows the user).
#
# Bounded: counts stop at 100000 files, and nothing here runs for any other command.

blast_summary() {
  BLAST=""; BLAST_UNSAVED=0
  local cmd="$1" n up dropped ci untracked t f rest
  case "$cmd" in
    *"git push"*)
      git rev-parse --git-dir >/dev/null 2>&1 || return 0
      if up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
        n=$(git rev-list --count "$up..HEAD" 2>/dev/null) || return 0
        dropped=$(git rev-list --count "HEAD..$up" 2>/dev/null || echo 0)
        ci=$(git diff --name-only "$up...HEAD" 2>/dev/null | grep -c '^\.github/workflows/' || true)
        BLAST="pushes $n commit(s) to $up"
      else
        n=$(git rev-list --count HEAD --not --remotes 2>/dev/null) || return 0
        dropped=0; ci=0
        BLAST="pushes $n commit(s) on a branch with no upstream yet"
      fi
      [ "${ci:-0}" -gt 0 ] && BLAST="$BLAST, touching $ci CI workflow file(s)"
      case "$cmd" in *--force*|*" -f"*|*--force-with-lease*)
        [ "${dropped:-0}" -gt 0 ] && BLAST="$BLAST; a force push DROPS $dropped commit(s) now on $up" ;;
      esac ;;
    *rm\ -*[rR]*|*rm\ --recursive*)
      n=0; untracked=0
      # Literal paths only: anything the shell would expand is not knowable here.
      # This rm's own arguments only: stop at the next command separator.
      rest="${cmd#*rm }"; rest="${rest%%[;&|]*}"
      for t in $(printf '%s\n' "$rest" | tr ' ' '\n' | grep -v '^-' | tr -d "\"'" | grep -v '[$*?`<>(){}~]' | head -20); do
        [ -e "$t" ] || continue
        f=$(find "$t" -type f 2>/dev/null | head -100001 | wc -l | tr -d ' ')
        n=$((n + f))
        # Untracked AND not ignored: work nobody saved. node_modules, build output and
        # everything else .gitignore names is regenerable, so it does not count.
        if git rev-parse --git-dir >/dev/null 2>&1; then
          untracked=$((untracked + $(git ls-files --others --exclude-standard -- "$t" 2>/dev/null | head -100001 | wc -l | tr -d ' ')))
        fi
      done
      [ "$n" -gt 0 ] || return 0
      BLAST_UNSAVED=$untracked
      BLAST="deletes $n file(s)"
      [ "$n" -gt 100000 ] && BLAST="deletes more than 100000 files"
      [ "$untracked" -gt 0 ] && BLAST="$BLAST, $untracked of them unsaved: not in git and not ignored, so there is no undo" ;;
  esac
  return 0
}
