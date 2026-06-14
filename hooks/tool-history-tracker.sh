#!/usr/bin/env bash
# Claude Supercharger — Tool History Tracker
# Event: PostToolUse | Matcher: (none, runs on every tool)
# Appends a JSONL entry per tool call to ~/.claude/supercharger/scope/.tool-history-<session_id>.
# Per-session file prevents cross-session data leakage when multiple Claude
# windows run concurrently. Consumed by confidence-gate.sh. Auto-trimmed to last 20 entries.
# Disable: SUPERCHARGER_CONFIDENCE=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_CONFIDENCE:-1}" = "0" ] && exit 0

_INPUT=$(cat)
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
HISTORY="$SCOPE_DIR/.tool-history-${SESSION_ID}"

ENTRY=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json, time
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = d.get('session_id', 'default')
tool = d.get('tool_name', '?')
resp = d.get('tool_response') or {}
exit_code = resp.get('exit_code')
err = resp.get('error') or d.get('error')
if exit_code is not None:
    success = exit_code == 0
elif err:
    success = False
else:
    success = True
print(json.dumps({'session_id': sid, 'tool': tool, 'success': success, 'ts': int(time.time())}))
" 2>/dev/null)

[ -z "$ENTRY" ] && exit 0

printf '%s\n' "$ENTRY" >> "$HISTORY"

if [ -f "$HISTORY" ]; then
  COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
  if [ "$COUNT" -gt 20 ]; then
    tail -n 20 "$HISTORY" > "$HISTORY.$$.tmp" && mv "$HISTORY.$$.tmp" "$HISTORY"
  fi
fi

exit 0
