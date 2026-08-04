#!/usr/bin/env bash
# Claude Supercharger — Record /add-dir Directories
# Event: DirectoryAdded | Matcher: (none)
#
# Claude Code has three ways to put a directory in the workspace: the `--add-dir`
# launch flag, the `/add-dir` in-session command, and the
# `permissions.additionalDirectories` setting. path-guard reads the settings key
# directly; the in-session command leaves no file behind, so this records it.
#
# Without this, `/add-dir ../sibling-repo` grants access at the Claude Code layer
# and path-guard still denies every write to it — a false block on a directory
# the user authorised explicitly, through the product's own front door.
#
# Recording only. The RECORD IS NOT TRUST: path-guard puts these through the same
# refusals as any configured root, so `/add-dir ~` cannot make the home directory
# writable. Appending here is deliberately cheap and permissive; the guard decides.
#
# Session-scoped, because a directory added in one session must not widen another.
#
# Disable: SUPERCHARGER_DIR_ADDED_RECORD=0
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "dir-added-record" && exit 0
[ "${SUPERCHARGER_DIR_ADDED_RECORD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read (no $(cat) fork).
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

SID="${CLAUDE_CODE_SESSION_ID:-}"
[ -z "$SID" ] && exit 0

# The DirectoryAdded payload shape is not documented, so read the plausible
# field names rather than betting on one. Same defensive approach agent-gate.sh
# takes for the agent identity field.
DIR=$(printf '%s\n' "$_INPUT" | jq -r '
  .directory //
  .dir //
  .path //
  .added_directory //
  .tool_input.directory //
  .tool_input.path //
  empty' 2>/dev/null || true)
[ -z "$DIR" ] && exit 0

case "$DIR" in
  /*) ;;                                  # absolute — use as-is
  *)  CWD=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
      [ -n "$CWD" ] && DIR="$CWD/$DIR" || exit 0 ;;
esac

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true
F="$SCOPE_DIR/.session-dirs-$SID"

# Skip if already recorded — /add-dir on the same path is idempotent for us, and
# an unbounded file would be re-read on every Edit/Write.
if [ -f "$F" ] && grep -Fxq "$DIR" "$F" 2>/dev/null; then
  exit 0
fi

# Bound the file. 100 added directories is far past any real workspace, and an
# unbounded list is re-read by path-guard on every single write.
if [ -f "$F" ] && [ "$(wc -l < "$F" 2>/dev/null | tr -d ' ')" -ge 100 ]; then
  exit 0
fi

printf '%s\n' "$DIR" >> "$F" 2>/dev/null || true
exit 0
