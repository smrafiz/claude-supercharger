#!/usr/bin/env bash
# Claude Supercharger — Git Safety Hook
# Event: PreToolUse | Matcher: Bash
# Blocks dangerous git operations. Exit 2 = block.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block force push to main/master
if echo "$COMMAND" | grep -qiE 'git push.*(--force|-f).*(main|master)'; then
  echo "BLOCKED by Supercharger: force push to main/master is not allowed" >&2
  exit 2
fi

# Block git reset --hard
if echo "$COMMAND" | grep -qiE 'git reset\s+--hard'; then
  echo "BLOCKED by Supercharger: git reset --hard can destroy uncommitted work" >&2
  exit 2
fi

# Block git checkout . / git restore .
if echo "$COMMAND" | grep -qiE 'git (checkout|restore)\s+\.'; then
  echo "BLOCKED by Supercharger: this discards all unstaged changes" >&2
  exit 2
fi

# Block git clean -f (removes untracked files)
if echo "$COMMAND" | grep -qiE 'git clean\s+(-f|--force)'; then
  echo "BLOCKED by Supercharger: git clean -f permanently removes untracked files" >&2
  exit 2
fi

exit 0
