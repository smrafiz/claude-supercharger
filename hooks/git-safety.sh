#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

CMD="$COMMAND"
CMD=$(echo "$CMD" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
CMD=$(echo "$CMD" | sed 's/^\\//')
while echo "$CMD" | grep -qE '^(sudo|command|env)[[:space:]]+'; do
  CMD=$(echo "$CMD" | sed -E 's/^(sudo|command|env)[[:space:]]+//')
done
CMD=$(echo "$CMD" | tr -s ' ')

block() {
  echo "BLOCKED by Supercharger git safety: $1" >&2
  echo "Command: $COMMAND" >&2
  exit 2
}

if echo "$CMD" | grep -qE '^git push[[:space:]]'; then
  has_force=false
  has_protected=false

  if echo "$CMD" | grep -qE '(^|[[:space:]])(--force|--force-with-lease|-f)([[:space:]]|$)'; then
    has_force=true
  fi

  if echo "$CMD" | grep -qE '(^|[[:space:]])(main|master)([[:space:]]|$)'; then
    has_protected=true
  fi

  if $has_force && $has_protected; then
    block "force push to protected branch"
  fi
fi

if echo "$CMD" | grep -qE '^git reset[[:space:]]' && echo "$CMD" | grep -qE '(^|[[:space:]])--hard([[:space:]]|$)'; then
  block "git reset --hard can destroy uncommitted work"
fi

if echo "$CMD" | grep -qE '^git (checkout|restore)[[:space:]]+\.$'; then
  block "discards all unstaged changes"
fi

if echo "$CMD" | grep -qE '^git clean[[:space:]]' && echo "$CMD" | grep -qE '(^|[[:space:]])(--force|-f)([[:space:]]|$)'; then
  block "git clean with force permanently removes untracked files"
fi

exit 0
