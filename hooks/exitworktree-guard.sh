#!/usr/bin/env bash
# Claude Supercharger — ExitWorktree Guard
# Event: PreToolUse | Matcher: ExitWorktree
# Asks before ExitWorktree deletes a worktree together with its uncommitted work.
#
# action=remove + discard_changes=true is the tool-channel twin of
# `git worktree remove --force`, which git-safety already ASKs on. The tool call
# never reaches Bash, so no guard saw it (#436). keep, or remove without
# discard_changes (the tool itself refuses when there is work to lose), is silent.
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "exitworktree-guard" && exit 0

. "$HOOKS_DIR/lib-stdin.sh"
. "$HOOKS_DIR/lib-deny.sh"; sc_read_input _INPUT

case "$_INPUT" in *discard_changes*) ;; *) exit 0 ;; esac

[ "$(printf '%s\n' "$_INPUT" | jq -r '(.tool_input.action == "remove" and .tool_input.discard_changes == true)' 2>/dev/null)" = "true" ] || exit 0

echo "[Supercharger] exitworktree-guard: ASK — remove with discard_changes" >&2
sc_ask "ExitWorktree remove with discard_changes=true deletes the worktree AND its uncommitted files and unmerged commits; they are not recoverable." \
  "confirm the work is committed or pushed elsewhere, or use action \"keep\"."
