#!/usr/bin/env bash
# Claude Supercharger — Stop Failure Logger
# Event: StopFailure | Matcher: (none)
# Logs API errors (rate limits, auth failures) to errors.log for diagnosis.

set -euo pipefail

INPUT=$(cat)

LOG_DIR="$HOME/.claude/supercharger"
LOG_FILE="$LOG_DIR/errors.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REASON=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('stop_reason') or d.get('error') or d.get('message') or 'unknown')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

printf '%s stop_failure reason=%s\n' "$TIMESTAMP" "$REASON" >> "$LOG_FILE"

# Rotate: keep last 500 lines
if [ -f "$LOG_FILE" ]; then
  LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
  if [ "$LINES" -gt 500 ]; then
    tail -400 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
fi

# Webhook if configured
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  webhook_enabled && send_webhook "[StopFailure] $REASON" || true
fi

echo "[Supercharger] stop-failure: logged reason=$REASON" >&2
exit 0
