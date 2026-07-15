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
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# v2.7.58: ONE python fork does both the session-id sanitize AND the entry build.
# Was jq (session_id) + python (entry) = 2 forks on EVERY PostToolUse — the
# highest-frequency event, and this hook can't be pre-gated (it must record every
# call for the confidence-gate). python already parsed the payload, so the jq was
# pure redundancy. Line 1 = sanitized session id, line 2 = entry JSON.
RESULT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json, time, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = re.sub(r'[^a-zA-Z0-9_-]', '', str(d.get('session_id') or 'default'))[:64] or 'default'
tool = d.get('tool_name', '?')
resp = d.get('tool_response')
# v2.7.30: PostToolUse tool_response has NO exit_code (it's
# {interrupted,isImage,noOutputExpected,stderr,stdout} for Bash) — reading it
# meant EVERY command logged as success, so confidence-gate never saw failures.
# Infer failure from interrupted + strong stderr markers, same as failure-tracker.
success = True
if isinstance(resp, dict):
    stderr = str(resp.get('stderr') or '')
    if resp.get('interrupted') is True:
        success = False
    elif resp.get('error') or d.get('error'):
        success = False
    elif re.search(r'command not found|Traceback|fatal:|ModuleNotFoundError|No such file or directory|Permission denied|npm ERR!|error:|panic:', stderr):
        success = False
print(sid)
print(json.dumps({'session_id': sid, 'tool': tool, 'success': success, 'ts': int(time.time())}))
" 2>/dev/null)

[ -z "$RESULT" ] && exit 0
SESSION_ID=${RESULT%%$'\n'*}
ENTRY=${RESULT#*$'\n'}
[ -z "$SESSION_ID" ] && SESSION_ID="default"
[ -z "$ENTRY" ] && exit 0
HISTORY="$SCOPE_DIR/.tool-history-${SESSION_ID}"

printf '%s\n' "$ENTRY" >> "$HISTORY"

if [ -f "$HISTORY" ]; then
  COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
  if [ "$COUNT" -gt 20 ]; then
    # v2.6.77: serialize the read-count-trim-replace under flock to prevent
    # last-writer-wins races when two async invocations both exceed 20 entries
    # at the same time (rare but plausible in tool-dense sessions).
    (
      flock -w 2 9 || true
      tail -n 20 "$HISTORY" > "$HISTORY.$$.tmp" && mv "$HISTORY.$$.tmp" "$HISTORY"
    ) 9>"$HISTORY.lock" 2>/dev/null || true
  fi
fi

exit 0
