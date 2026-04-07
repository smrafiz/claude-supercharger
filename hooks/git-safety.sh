#!/usr/bin/env bash
set -euo pipefail

COMMAND=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

CMD="$COMMAND"
CMD=$(printf '%s\n' "$CMD" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
CMD=$(printf '%s\n' "$CMD" | sed 's/^\\//')
while printf '%s\n' "$CMD" | grep -qE '^(sudo|command|env)[[:space:]]+'; do
  CMD=$(printf '%s\n' "$CMD" | sed -E 's/^(sudo|command|env)[[:space:]]+//')
done
CMD=$(printf '%s\n' "$CMD" | tr -s ' ')

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

if printf '%s\n' "$CMD" | grep -qE '^git (checkout|restore)[[:space:]]+\.$'; then
  block "discards all unstaged changes"
fi

if printf '%s\n' "$CMD" | grep -qE '^git clean[[:space:]]' && printf '%s\n' "$CMD" | grep -qE '(^|[[:space:]])(--force|-f)([[:space:]]|$)'; then
  block "git clean with force permanently removes untracked files"
fi

exit 0
