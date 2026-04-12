#!/usr/bin/env bash
# Claude Supercharger — Context Advisor
# Event: UserPromptSubmit | Matcher: (none)
# Injects context warnings and economy suggestions based on context window usage.

set -euo pipefail

_INPUT=$(cat)

PCT=$(printf '%s\n' "$_INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
if [ -z "$PCT" ]; then
  PCT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
pct = data.get('context_window', {}).get('used_percentage', '')
print(int(pct) if pct != '' else '')
" 2>/dev/null || echo "")
fi

[ -z "$PCT" ] && exit 0

PCT=${PCT%%.*}

echo "[Supercharger] context-advisor: ${PCT}% used" >&2

if [ "$PCT" -lt 50 ]; then
  exit 0
elif [ "$PCT" -lt 80 ]; then
  MSG="[CONTEXT] At ${PCT}% context. Consider /compact if conversation continues."
elif [ "$PCT" -lt 90 ]; then
  MSG="[CONTEXT WARNING] At ${PCT}% context. Run /compact now. Consider: eco minimal. Before compacting, verify: tests pass, build clean, no uncommitted work."
else
  MSG="[CONTEXT CRITICAL] At ${PCT}% — near limit. STOP. Verify work is complete before compacting or starting fresh."
fi

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
