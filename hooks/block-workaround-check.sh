#!/usr/bin/env bash
# Claude Supercharger — Block Workaround Check
# Event: PreToolUse | Matcher: Bash,Monitor,PowerShell,Write,Edit,MultiEdit,NotebookEdit
#
# After a guard denies a file (lib-deny.sh records its name for the session), a
# later call that names the same file is often the same act by another route: a
# script the agent writes that writes it, a redirect, a package.json hook,
# `python -c "open('.env','w')"`. Each is allowed on its face, because the guard
# that blocked the first attempt decided from a path it never sees again.
# "A block is final" was only a rule the model reads; this makes it visible.
#
# WARNS, never denies: a comment explaining why the agent left `.env` alone names
# it too. Once per file per session. Idea from yerinsabraham/trackline's
# "workaround" check (Apache-2.0); independently implemented.
#
# Hot path: one regex for the session id, one file test. No fork until a file in
# this session was actually denied.
# Disable: SUPERCHARGER_BLOCK_WORKAROUND=0

[ "${SUPERCHARGER_BLOCK_WORKAROUND:-1}" = "0" ] && exit 0
# shellcheck source=hooks/lib-suppress.sh
. "${BASH_SOURCE[0]%/*}/lib-suppress.sh" 2>/dev/null || true
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"; sc_read_input _INPUT

[[ "$_INPUT" =~ \"session_id\":[[:space:]]*\"([A-Za-z0-9_-]+)\" ]] || exit 0
_BW_DIR="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}/scope"
_BW_LIST="$_BW_DIR/.blocked-files-${BASH_REMATCH[1]}"
[ -s "$_BW_LIST" ] || exit 0
_BW_WARNED="$_BW_LIST.warned"

# The name must stand on its own: `.env` matches, `.env.example` and `my.env` do not.
_BW_EDGE='A-Za-z0-9_.-'
_bw_hit=""
while IFS= read -r _bw_name; do
  [ -n "$_bw_name" ] || continue
  grep -qxF -- "$_bw_name" "$_BW_WARNED" 2>/dev/null && continue
  _bw_re=$(printf '%s' "$_bw_name" | sed 's/[][\.*^$+?(){}|/]/\\&/g')
  if [[ "$_INPUT" =~ (^|[^$_BW_EDGE])${_bw_re}([^$_BW_EDGE]|$) ]]; then
    _bw_hit="$_bw_name"; break
  fi
done < "$_BW_LIST"
[ -n "$_bw_hit" ] || exit 0

printf '%s\n' "$_bw_hit" >> "$_BW_WARNED" 2>/dev/null || true
_msg="Supercharger: $_bw_hit was blocked earlier in this session, and this call names it again. If it reaches that file another way (a script, a redirect, an interpreter, a build step), that is the act the block refused: stop and tell the user instead. If it only mentions the file, carry on."
. "${BASH_SOURCE[0]%/*}/lib-deny.sh"
_sc_json_escape "$_msg"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$_SC_JSON"
exit 0
