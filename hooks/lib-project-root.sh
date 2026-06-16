#!/usr/bin/env bash
# Claude Supercharger — Project root resolver
#
# In a git worktree, $cwd points at the *linked* worktree (e.g.
# /repo/feat-branch), not the main repo (/repo). Project-level config like
# .supercharger.json typically lives in the main repo. A naive walk up from
# $cwd misses it.
#
# `_resolve_project_root <cwd>` returns:
#   - the main worktree's root, if $cwd is a linked worktree
#   - $cwd otherwise (non-git dir, or main worktree)
#
# Fast path: in a linked worktree, $cwd/.git is a FILE (gitdir: pointer);
# in the main worktree it's a DIR; in non-git dirs it's absent. So we only
# fork `git rev-parse` when $cwd/.git is a file — ~0.5ms in the common case,
# ~10ms when we actually need to resolve.

_resolve_project_root() {
  local cwd="${1:-$PWD}"
  if [ ! -f "$cwd/.git" ]; then
    printf '%s\n' "$cwd"
    return
  fi
  local out common git
  out=$(cd "$cwd" 2>/dev/null && git rev-parse --git-common-dir --git-dir 2>/dev/null) \
    || { printf '%s\n' "$cwd"; return; }
  common=$(printf '%s\n' "$out" | head -1)
  git=$(printf '%s\n' "$out" | tail -1)
  if [ "$common" != "$git" ] && [ -n "$common" ]; then
    (cd "$cwd" && cd "$(dirname "$common")" 2>/dev/null && pwd) \
      || printf '%s\n' "$cwd"
  else
    printf '%s\n' "$cwd"
  fi
}
