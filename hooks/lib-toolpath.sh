#!/usr/bin/env bash
# Claude Supercharger — tool-supplied path normalisation (v4.0.29)
#
# The harness accepts path spellings that bash's `[ -f ]` rejects. Where the two
# disagree, the TOOL acts on the real file and the GUARD sees nothing — it stats
# a path that cannot exist, takes its "no such file, nothing to do" exit, and
# says nothing. Measured against the deployed artifact guard, same file:
#
#   file_path "/Users/me/.probe/p.html"    rc=2, deny
#   file_path "~/.probe/p.html"            rc=0, silent    <- harness reads it
#
# Confirmed by asking the harness directly, not by reasoning about it:
#
#   ~/path            EXPANDED by the harness, not by [ -f ]   -> bypass
#   "  /abs/path"     leading whitespace tolerated              -> bypass
#   $HOME/path        NOT expanded — the tool fails too         -> no bypass
#   ["/abs/path"]     coerced, and the tool fails too           -> no bypass
#
# The last two matter as much as the first two: a fix for them would be a guess
# dressed as caution, and would ask on calls that can never succeed.
#
# Worst case is not the content scanners. path-guard resolves a non-absolute
# path against cwd, so `~/elsewhere/x` became `<project>/~/elsewhere/x` — INSIDE
# the project boundary — and a write outside the project read as a write within
# it. lib-smart-approve stats the same way to decide what autopilot may
# auto-approve.
#
# Normalise where the value is READ, not at each comparison, because these
# hooks then stat, glob and prefix-match it in several places each.
# [[one-path-many-spellings]] — fifth and sixth spellings on that list.

# sc_norm_path VARNAME — rewrite the named variable in place.
# Whitespace-trims, then expands a leading ~ or ~/ using $HOME. Everything else
# is left exactly as given: relative paths still belong to the caller, which
# already resolves them against the payload's cwd.
sc_norm_path() {
  local _sc_np_v="$1" _sc_np_p="${!1}"
  # Trim surrounding whitespace (bash 3.2: no ${var@Q}, no extglob assumed).
  _sc_np_p="${_sc_np_p#"${_sc_np_p%%[![:space:]]*}"}"
  _sc_np_p="${_sc_np_p%"${_sc_np_p##*[![:space:]]}"}"
  # Only the HOME forms. `~user/...` is deliberately NOT expanded: resolving it
  # needs the passwd database, the harness was not observed to accept it, and a
  # wrong guess here silently retargets a security check at another user's file.
  case "$_sc_np_p" in
    '~')    _sc_np_p="$HOME" ;;
    '~/'*)  _sc_np_p="$HOME/${_sc_np_p#\~/}" ;;
  esac
  printf -v "$_sc_np_v" '%s' "$_sc_np_p"
}
