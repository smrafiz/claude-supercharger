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
CMD=$(echo "$CMD" | sed -E 's/^(sudo|command|env)[[:space:]]+//')
CMD=$(echo "$CMD" | tr -s ' ')

block() {
  echo "BLOCKED by Supercharger safety hook: $1" >&2
  echo "Command: $COMMAND" >&2
  exit 2
}

if echo "$CMD" | grep -qE '^rm[[:space:]]'; then
  has_recursive=false
  has_force=false

  set +e
  args="${CMD#rm }"

  if echo "$args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$)' || \
     echo "$args" | grep -qE '(^|[[:space:]])--recursive([[:space:]]|$)'; then
    has_recursive=true
  fi

  if echo "$args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)' || \
     echo "$args" | grep -qE '(^|[[:space:]])--force([[:space:]]|$)'; then
    has_force=true
  fi
  set -e

  if $has_recursive && $has_force; then
    if echo "$args" | grep -qE '(^|[[:space:]])(\/[[:space:]]*$|\/\*|~|\$HOME|\.\.)([[:space:]]|$)'; then
      block "recursive force rm on dangerous target"
    fi
  fi
fi

DANGEROUS_PATTERNS=(
  'DROP[[:space:]]+TABLE'
  'DROP[[:space:]]+DATABASE'
  'chmod[[:space:]]+(-R[[:space:]]+)?777'
  'mkfs\.'
  'dd[[:space:]]+if='
  '>[[:space:]]*/dev/sd'
  'curl.*\|.*bash'
  'curl.*\|.*sh'
  'wget.*\|.*bash'
  'wget.*\|.*sh'
  'truncate[[:space:]]+-s[[:space:]]*0'
  ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:'
  'kill[[:space:]]+-9[[:space:]]+-1'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qiE "$pattern"; then
    block "dangerous pattern: $pattern"
  fi
done

if echo "$CMD" | grep -qE '^mv[[:space:]]+(\/|~|\$HOME)[[:space:]]'; then
  block "mv from root or home directory"
fi

exit 0
