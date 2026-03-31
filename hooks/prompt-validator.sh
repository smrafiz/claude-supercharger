#!/usr/bin/env bash
# Claude Supercharger — Prompt Validator Hook
# Event: UserPromptSubmit | Matcher: (none)
# Scans prompt for anti-patterns. Adds notes, never blocks.

set -euo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('prompt',''))" 2>/dev/null || echo "")

if [ -z "$PROMPT" ]; then
  exit 0
fi

NOTES=""

# Check for vague scope
if echo "$PROMPT" | grep -qiE '^(fix|update|change|improve|make)\s+(it|this|that|the app|the code)\b'; then
  NOTES="${NOTES}[Supercharger] Consider specifying which files or functions to target.\n"
fi

# Check for multiple tasks
if echo "$PROMPT" | grep -qiE '\b(and also|and then|plus|additionally)\b.*\b(and also|and then|plus|additionally)\b'; then
  NOTES="${NOTES}[Supercharger] Multiple tasks detected. Consider splitting into separate requests.\n"
fi

# Check for vague success criteria
if echo "$PROMPT" | grep -qiE '\b(make it better|improve|optimize|clean up)\b' && ! echo "$PROMPT" | grep -qiE '\b(should|must|ensure|so that|such that)\b'; then
  NOTES="${NOTES}[Supercharger] Consider adding success criteria (what does 'better' mean here?).\n"
fi

if [ -n "$NOTES" ]; then
  echo -e "$NOTES" >&2
fi

exit 0
