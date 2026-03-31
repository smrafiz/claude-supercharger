#!/usr/bin/env bash
# Claude Supercharger — Safety Hook
# Event: PreToolUse | Matcher: Bash
# Blocks destructive commands. Exit 2 = block execution.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

DANGEROUS_PATTERNS=(
  'rm -rf /'
  'rm -rf ~'
  'rm -rf \$HOME'
  'rm -rf \.\.'
  'DROP TABLE'
  'DROP DATABASE'
  'chmod 777'
  'chmod -R 777'
  'mkfs\.'
  'dd if='
  '> /dev/sd'
  'curl.*|.*bash'
  'curl.*|.*sh'
  'wget.*|.*bash'
  'wget.*|.*sh'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    echo "BLOCKED by Supercharger safety hook: destructive command detected" >&2
    echo "Pattern matched: $pattern" >&2
    echo "Command: $COMMAND" >&2
    exit 2
  fi
done

exit 0
