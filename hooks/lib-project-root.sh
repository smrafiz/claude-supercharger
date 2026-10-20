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
  # Accept the redirect only for a REAL linked worktree, linked the way git links
  # one: the git dir sits at <common>/worktrees/<name>, and its `gitdir` file points
  # back at this .git. `.git` and `commondir` are plain files, so a downloaded
  # archive can forge both and point the root at any directory, whose
  # .supercharger.json would then be loaded silently (the CVE-2026-40068 class).
  if [ "$common" != "$git" ] && [ -n "$common" ]; then
    local c g back
    c=$(cd "$cwd" 2>/dev/null && cd "$common" 2>/dev/null && pwd -P) || c=""
    g=$(cd "$cwd" 2>/dev/null && cd "$git" 2>/dev/null && pwd -P) || g=""
    back=$(head -1 "$g/gitdir" 2>/dev/null || true)
    # git may write this link relative to the git dir (worktree.useRelativePaths).
    back=$(cd "$g" 2>/dev/null && cd "$(dirname "$back")" 2>/dev/null && pwd -P)/$(basename "$back")
    if [ -z "$c" ] || [ "${g%/*}" != "$c/worktrees" ] || [ "$back" != "$(cd "$cwd" && pwd -P)/.git" ]; then
      printf '%s\n' "$cwd"; return
    fi
  fi
  if [ "$common" != "$git" ] && [ -n "$common" ]; then
    (cd "$cwd" && cd "$(dirname "$common")" 2>/dev/null && pwd) \
      || printf '%s\n' "$cwd"
  else
    printf '%s\n' "$cwd"
  fi
}
