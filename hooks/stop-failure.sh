#!/usr/bin/env bash
# Claude Supercharger — Stop Failure Logger
# Event: StopFailure | Matcher: (none)
# Logs API errors (rate limits, auth failures) to errors.log for diagnosis.

set -euo pipefail

_INPUT=$(cat)

LOG_DIR="$HOME/.claude/supercharger"
LOG_FILE="$LOG_DIR/errors.log"
mkdir -p "$LOG_DIR"

# v2.6.37: one python3 fork replaces 2 (stdin reason extract + ADVICE_JSON
# wrap). Now: parse stdin, classify reason, emit advice JSON inline. ~80ms → ~50ms.
RESULT=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys

raw = os.environ.get('HOOK_INPUT', '')
try:
    d = json.loads(raw)
except Exception:
    d = {}

# Search across multiple fields — stop_reason may carry a generic "error" while
# the specific class (rate_limit_error, authentication_failed, billing_error)
# lives in .error. Walk all three and pick the first that matches an advice key.
reason_candidates = [
    str(d.get('stop_reason') or ''),
    str(d.get('error') or ''),
    str(d.get('message') or ''),
]
reason = reason_candidates[0] or reason_candidates[1] or reason_candidates[2] or 'unknown'

advice_map = (
    ('rate_limit', '[STOP FAILURE] Rate limit reached. Pause for 60 seconds before retrying. Do not loop or retry immediately.'),
    ('authentication_failed', "[STOP FAILURE] Authentication failed. The user may need to run 'claude login' to re-authenticate."),
    ('billing_error', '[STOP FAILURE] Billing issue detected. The user should check their subscription at claude.ai/settings.'),
)
advice = ''
for cand in reason_candidates:
    if not cand:
        continue
    match = next((msg for prefix, msg in advice_map if cand.startswith(prefix) or prefix in cand), '')
    if match:
        advice = match
        break

# Emit two lines: reason on line 1 (for bash log), JSON on line 2 (or empty)
# v2.7.40: StopFailure is context-only — advice must ride hookSpecificOutput.
# additionalContext, not stopReason (which only applies with continue:false).
print(reason)
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'StopFailure', 'additionalContext': advice}}) if advice else '')
PYEOF
)
REASON=$(printf '%s\n' "$RESULT" | sed -n '1p')
ADVICE_JSON=$(printf '%s\n' "$RESULT" | sed -n '2p')
[ -z "$REASON" ] && REASON="unknown"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '%s stop_failure reason=%s\n' "$TIMESTAMP" "$REASON" >> "$LOG_FILE"

if [ -n "$ADVICE_JSON" ]; then
  printf '%s\n' "$ADVICE_JSON"
fi

# Rotate: keep last 500 lines
if [ -f "$LOG_FILE" ]; then
  LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
  if [ "$LINES" -gt 500 ]; then
    tail -400 "$LOG_FILE" > "$LOG_FILE.$$.tmp" && mv "$LOG_FILE.$$.tmp" "$LOG_FILE"
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
