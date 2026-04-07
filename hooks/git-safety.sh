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
  exit 2
}

if printf '%s\n' "$CMD" | grep -qE '^git push[[:space:]]'; then
  has_force=false
  has_protected=false

  if printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])(--force|--force-with-lease|-f)([[:space:]]|$)'; then
    has_force=true
  fi

  if printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])(main|master)([[:space:]]|$)'; then
    has_protected=true
  fi

  if $has_force && $has_protected; then
    block "force push to protected branch"
  fi
fi

if printf '%s\n' "$CMD" | grep -qE '^git reset[[:space:]]' && printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])--hard([[:space:]]|$)'; then
  block "git reset --hard can destroy uncommitted work"
fi

if printf '%s\n' "$CMD" | grep -qE '^git (checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)'; then
  block "discards all unstaged changes"
fi

if printf '%s\n' "$CMD" | grep -qE '^git clean[[:space:]]' && printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])(--force|-f)([[:space:]]|$)'; then
  block "git clean with force permanently removes untracked files"
fi

if printf '%s\n' "$CMD" | grep -qE '^git branch[[:space:]]' && printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])-D([[:space:]]|$)'; then
  if printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])(main|master)([[:space:]]|$)'; then
    block "force-deleting a protected branch (main/master)"
  fi
fi

if printf '%s\n' "$CMD" | grep -qE '^git stash (drop|clear)([[:space:]]|$)'; then
  block "git stash drop/clear permanently removes stashed changes"
fi

exit 0
