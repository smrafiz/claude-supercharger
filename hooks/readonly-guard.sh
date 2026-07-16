#!/usr/bin/env bash
# Claude Supercharger — Read-only mode enforcer
# Event: PreToolUse | Matcher: Write,Edit,MultiEdit,NotebookEdit,Bash
#
# While a read-only window is active (/sc-readonly), blocks every file edit and every
# mutating Bash command; reads/searches/planning pass. The inverse of autopilot — a
# time-boxed TIGHTENING. This is a WORKFLOW guard ("look, don't touch"), not a
# security sandbox: precise for the editor tools, best-effort for Bash (an obscure
# mutator may slip). The always-on safety hooks (safety.sh etc.) are the real floor.
#
# Precedence: this is a PreToolUse deny, so it beats autopilot's PermissionRequest
# auto-approve automatically (a denied call never reaches approval) — tighten > loosen.
#
# Window flags (per-session preferred, global fallback), same convention as autopilot:
#   scope/.readonly-until-<session-id>   scope/.readonly-until
set -uo pipefail

# Fast-path: if NO read-only flag exists anywhere, do nothing (near-zero overhead on
# every Write/Edit/Bash when the mode is off). Resolve state inline before sourcing libs.
_SC_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
_FLAGS=("$_SC_STATE"/scope/.readonly-until*)
[ -e "${_FLAGS[0]:-}" ] || exit 0

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "readonly-guard" && exit 0

# Is a read-only window active for this call? (global OR this session's flag)
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
NOW=$(date +%s 2>/dev/null || echo 0)
_active=false
for _f in "$SUPERCHARGER_STATE/scope/.readonly-until" ${SID:+"$SUPERCHARGER_STATE/scope/.readonly-until-$SID"}; do
  [ -f "$_f" ] || continue
  _u=$(cat "$_f" 2>/dev/null || echo 0)
  if printf '%s' "$_u" | grep -qE '^[0-9]+$' && [ "$_u" -gt "$NOW" ]; then _active=true; break; fi
done
$_active || exit 0

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

block() {
  local what="$1"
  echo "" >&2
  echo "Supercharger read-only mode is ON — $what blocked." >&2
  echo "  Reads, searches, and planning are allowed; edits and mutating commands are paused." >&2
  echo "  Turn it off with: /sc-readonly off" >&2
  echo "" >&2
  local rsn="Read-only mode is active (/sc-readonly) — $what is blocked. Turn it off with /sc-readonly off, or wait for the window to expire."
  RSN=$(printf '%s' "$rsn" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"read-only mode active"')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# Editor tools always mutate → block.
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit) block "a file edit" ;;
esac

# Bash: block mutating commands; allow read-only ones.
if [ "$TOOL" = "Bash" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  [ -z "$CMD" ] && exit 0

  # File-writing verbs at a word boundary.
  printf '%s\n' "$CMD" | grep -qE '(^|[;&|(]|[[:space:]])(rm|rmdir|mv|cp|mkdir|touch|chmod|chown|chgrp|ln|dd|tee|truncate|unlink|shred|mkfifo|mknod|install)([[:space:]]|$)' && block "a mutating command"
  # In-place stream editors (sed -i / perl -i).
  printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])(sed|perl)[[:space:]][^|]*-i' && block "an in-place edit"
  # git write sub-commands (status/log/diff/show/remote stay allowed).
  printf '%s\n' "$CMD" | grep -qE '(^|[;&|(]|[[:space:]])git[[:space:]]+(commit|push|add|mv|rm|merge|rebase|reset|checkout|restore|stash|clean|apply|am|cherry-pick|revert|init|clone|pull|fetch|tag|branch)([[:space:]]|$)' && block "a git write command"
  # Package installs / mutations.
  printf '%s\n' "$CMD" | grep -qE '(^|[;&|(]|[[:space:]])(npm|yarn|pnpm|bun)[[:space:]]+(install|add|ci|i|update|upgrade|remove|uninstall|link|prune|dedupe)([[:space:]]|$)' && block "a package change"
  printf '%s\n' "$CMD" | grep -qE '(^|[;&|(]|[[:space:]])(pip[0-9]?|pipx)[[:space:]]+(install|uninstall)([[:space:]]|$)' && block "a package change"
  printf '%s\n' "$CMD" | grep -qE '(^|[;&|(]|[[:space:]])(gem|brew|apt|apt-get|dnf|yum|pacman|cargo|go|gcloud|aws)[[:space:]]+[a-z-]*(install|add|update|upgrade|remove|uninstall|publish|create|apply|deploy)([[:space:]]|$)' && block "an install/deploy command"
  # Output redirection to a real file (allow /dev/null-style sinks).
  if printf '%s\n' "$CMD" | grep -oE '>>?[[:space:]]*[^[:space:]&|;)]+' | grep -qvE '>>?[[:space:]]*/dev/(null|stderr|stdout|tty)'; then
    block "a redirect that writes a file"
  fi
fi

exit 0
