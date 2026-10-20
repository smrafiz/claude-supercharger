#!/usr/bin/env bash
# Claude Supercharger — Blast Radius Guard
# Event: PreToolUse | Matcher: Bash,Monitor,PowerShell
#
# Asks before a recursive rm that would delete UNSAVED work: files that are neither
# in git nor ignored. Those have no undo, and the prompt Claude Code would show says
# only `rm -rf dir`, not that 3 of the 400 files inside were never committed.
# Ignored files (node_modules, build output, caches) do not count, so ordinary
# cleanups stay silent; outside a git repo there is nothing to compare with and it
# stays silent too. The ask carries the count (lib-blast.sh), so the prompt says
# what is lost. safety.sh still denies the dangerous targets (/, ~, ...) first.
# Disable: SUPERCHARGER_BLAST=0
set -uo pipefail
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true
[ "${SUPERCHARGER_BLAST:-1}" = 0 ] && exit 0
# shellcheck source=hooks/lib-stdin.sh
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"; sc_read_input _INPUT
# Fast exit: nothing that is not a recursive rm pays a fork.
case "$_INPUT" in *'rm '*) ;; *) exit 0 ;; esac
CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
case "$CMD" in *rm\ -*[rR]*|*rm\ --recursive*) ;; *) exit 0 ;; esac
CWD=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && { cd "$CWD" 2>/dev/null || exit 0; }

# shellcheck source=hooks/lib-blast.sh
. "${BASH_SOURCE[0]%/*}/lib-blast.sh" 2>/dev/null || exit 0
blast_summary "$CMD"
[ "${BLAST_UNSAVED:-0}" -gt 0 ] || exit 0

# shellcheck source=hooks/lib-deny.sh
. "${BASH_SOURCE[0]%/*}/lib-deny.sh"
# sc_decision appends the Effect line itself (it sees CMD); CMD stays set for it.
sc_ask "this recursive rm deletes files that were never committed and are not ignored." \
  "commit or move what you want to keep first, or confirm it is disposable"
