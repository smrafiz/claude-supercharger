#!/usr/bin/env bash
# Claude Supercharger — Context Advisor
# Event: UserPromptSubmit | Matcher: (none)
# Injects context warnings and economy suggestions based on context window usage.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

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

if [ "$PCT" -lt 70 ]; then
  exit 0
elif [ "$PCT" -lt 80 ]; then
  MSG="[CTX] ${PCT}% used. /compact if continuing."
elif [ "$PCT" -lt 90 ]; then
  MSG="[CTX WARN] ${PCT}% — run /compact now. eco minimal. Verify: tests pass, build clean, no uncommitted work."
else
  MSG="[CTX CRITICAL] ${PCT}% — near limit. Stop and verify work before compacting."
fi

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
