#!/usr/bin/env bash
# Claude Supercharger — Context Monitor
# Event: UserPromptSubmit | Matcher: (none)
# Injects additionalContext warnings when context window usage crosses thresholds.

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

# Strip decimals
PCT=${PCT%%.*}

echo "[Supercharger] context-monitor: ${PCT}% used" >&2

if [ "$PCT" -lt 50 ]; then
  exit 0
elif [ "$PCT" -lt 70 ]; then
  MSG="[CONTEXT] At ${PCT}% context. Consider /compact if this conversation continues much longer."
elif [ "$PCT" -lt 90 ]; then
  MSG="[CONTEXT WARNING] At ${PCT}% context. Run /compact now to preserve working memory. Key decisions will be lost after compaction unless summarized."
else
  MSG="[CONTEXT CRITICAL] At ${PCT}% context — near limit. Stop new work. Run /compact immediately or start a fresh session."
fi

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
