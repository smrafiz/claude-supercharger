#!/usr/bin/env bash
set -euo pipefail

_INPUT=$(cat)
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

block() {
  echo "" >&2
  echo "Supercharger blocked this git operation." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  local blocks_log="$HOME/.claude/supercharger/scope/.blocked-commands"
  mkdir -p "$(dirname "$blocks_log")" 2>/dev/null || true
  local safe_cmd="${COMMAND:0:120}"
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$safe_cmd" >> "$blocks_log" 2>/dev/null || true
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 2
}

rewrite() {
  local safe_cmd="$1" reason="$2"
  echo "[Supercharger] git-safety: rewrote unsafe command — ${reason}" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":%s}}}\n' \
    "$(printf '%s' "$safe_cmd" | jq -Rs '.')"
  exit 0
}

if [[ "$CMD" =~ ^git\ push[[:space:]] ]]; then
  has_force=false
  has_protected=false

  if [[ "$CMD" =~ (^|[[:space:]])(--force|--force-with-lease|-f)([[:space:]]|$) ]]; then
    has_force=true
  fi

  if [[ "$CMD" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]]; then
    has_protected=true
  fi

  if $has_force && $has_protected; then
    block "force push to protected branch"
  elif $has_force; then
    # Non-protected branch — strip force flag, push safely
    safe=$(printf '%s\n' "$CMD" | sed -E 's/(^|[[:space:]])(--force-with-lease|--force|-f)([[:space:]]|$)/ /g' | tr -s ' ' | sed 's/[[:space:]]*$//')
    rewrite "$safe" "stripped --force from non-protected branch push"
  fi
fi

if [[ "$CMD" =~ ^git\ reset[[:space:]] ]] && [[ "$CMD" =~ (^|[[:space:]])--hard([[:space:]]|$) ]]; then
  block "git reset --hard can destroy uncommitted work"
fi

if [[ "$CMD" =~ ^git\ (checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$) ]]; then
  block "discards all unstaged changes"
fi

if [[ "$CMD" =~ ^git\ clean[[:space:]] ]] && [[ "$CMD" =~ (^|[[:space:]])(--force|-f)([[:space:]]|$) ]]; then
  block "git clean with force permanently removes untracked files"
fi

if [[ "$CMD" =~ ^git\ branch[[:space:]] ]] && [[ "$CMD" =~ (^|[[:space:]])-D([[:space:]]|$) ]]; then
  if [[ "$CMD" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]]; then
    block "force-deleting a protected branch (main/master)"
  fi
fi

if [[ "$CMD" =~ ^git\ stash\ (drop|clear)([[:space:]]|$) ]]; then
  block "git stash drop/clear permanently removes stashed changes"
fi

exit 0
