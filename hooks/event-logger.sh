#!/usr/bin/env bash
# Claude Supercharger — Misc Event Logger
# Events: PermissionDenied, PostToolUseFailure, SubagentStop, ConfigChange
# Logs to ~/.claude/supercharger/events.log (async, no output to Claude)

set -euo pipefail

EVENT_TYPE="${1:-unknown}"
INPUT=$(cat)

LOG_DIR="$HOME/.claude/supercharger"
LOG_FILE="$LOG_DIR/events.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

DETAIL=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ev = sys.argv[1] if len(sys.argv) > 1 else 'unknown'
    if ev == 'permission_denied':
        tool = d.get('tool_name') or d.get('tool') or '?'
        reason = (d.get('reason') or d.get('message') or '?')[:80]
        print(f'tool={tool} reason={reason}')
    elif ev == 'tool_failure':
        tool = d.get('tool_name') or '?'
        error = (d.get('error') or d.get('message') or '?')[:80]
        print(f'tool={tool} error={error}')
    elif ev == 'subagent_stop':
        name = d.get('agent_name') or d.get('name') or '?'
        print(f'agent={name}')
    elif ev == 'config_change':
        key = d.get('key') or d.get('path') or d.get('setting') or '?'
        print(f'key={key}')
    else:
        print('detail=unknown')
except Exception:
    print('parse_error')
" "$EVENT_TYPE" 2>/dev/null || echo "parse_error")

printf '%s %s %s\n' "$TIMESTAMP" "$EVENT_TYPE" "$DETAIL" >> "$LOG_FILE"

# Rotate: keep last 500 lines
LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
if [ "$LINES" -gt 500 ]; then
  tail -400 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

exit 0
