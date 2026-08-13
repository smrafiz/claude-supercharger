#!/usr/bin/env bash
# Claude Supercharger — Misc Event Logger
# Event: PermissionDenied | PostToolUseFailure | SubagentStop | ConfigChange | InstructionsLoaded | TaskCreated | TaskCompleted | TeammateIdle | Matcher: (none)
# Logs to ~/.claude/supercharger/events.log (async, no output to Claude)

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

EVENT_TYPE="${1:-unknown}"
# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.7.16: SubagentStop re-fires (stop_hook_active) — log the subagent once, not
# ~10x per agent.
if [ "$EVENT_TYPE" = "subagent_stop" ]; then
  case "$_INPUT" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;; esac
fi

# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

LOG_DIR="$SUPERCHARGER_STATE"
LOG_FILE="$LOG_DIR/events.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

DETAIL=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json, re

# Every field below comes from a tool payload, so none of it is safe to write
# raw. The clean() helper is what makes this a one-line-per-event ledger: the
# tool_failure branch truncated to 80 chars but never touched newlines, so a
# Bash failure whose stderr held a traceback wrote those 80 characters ACROSS
# LINES. The live log shows it — 15 orphan lines, one of them a bare '20',
# another 'File \"<stdin>\", line 2, in <mod'. Every line-wise consumer sees
# those as events, and the 500-line rotation below trims by line, so one noisy
# failure evicts real history.
def clean(v, n=80):
    s = ' '.join(str(v if v is not None else '?').split())   # newlines/tabs out
    s = re.sub(r'[\x00-\x1f\x7f]', '', s)                    # control bytes out
    return s[:n] or '?'

try:
    d = json.load(sys.stdin)
    ev = sys.argv[1] if len(sys.argv) > 1 else 'unknown'
    if ev == 'permission_denied':
        tool = clean(d.get('tool_name') or d.get('tool') or '?', 40)
        reason = clean(d.get('reason') or d.get('message') or '?')
        print(f'tool={tool} reason={reason}')
    elif ev == 'tool_failure':
        tool = clean(d.get('tool_name') or '?', 40)
        error = clean(d.get('error') or d.get('message') or '?')
        print(f'tool={tool} error={error}')
    elif ev == 'subagent_stop':
        name = clean(d.get('agent_name') or d.get('name') or '?', 60)
        print(f'agent={name}')
    elif ev == 'config_change':
        key = clean(d.get('key') or d.get('path') or d.get('setting') or '?', 60)
        print(f'key={key}')
    elif ev == 'instructions_loaded':
        fp = clean(d.get('file_path') or '?', 120)
        reason = clean(d.get('load_reason') or '?', 30)
        mtype = clean(d.get('memory_type') or '?', 30)
        print(f'file={fp} reason={reason} type={mtype}')
    elif ev == 'task_created':
        name = clean(d.get('task_name') or d.get('name') or d.get('task_id') or '?', 60)
        print(f'task={name}')
    elif ev == 'task_completed':
        name = clean(d.get('task_name') or d.get('name') or d.get('task_id') or '?', 60)
        status = clean(d.get('status') or d.get('result') or 'done', 30)
        print(f'task={name} status={status}')
    elif ev == 'teammate_idle':
        agent = clean(d.get('agent_id') or d.get('agent_name') or '?', 60)
        print(f'agent={agent}')
    else:
        print('detail=unknown')
except Exception:
    print('parse_error')
" "$EVENT_TYPE" 2>/dev/null || echo "parse_error")

# A tool's own error text lands in this file, so it goes through the SAME secret
# list as tool output, commits, and cross-session messages — an error message is
# a place credentials show up (a failed curl echoing its URL, a driver printing a
# connection string). Detection, not substitution: these are POSIX EREs with
# [[:space:]] classes that python's re would silently mis-parse, so the match is
# left to grep and a hit replaces the whole detail rather than editing it.
# shellcheck source=hooks/lib-secret-patterns.sh
. "${BASH_SOURCE[0]%/*}/lib-secret-patterns.sh" 2>/dev/null || true
if [ "${#SECRET_PATTERNS[@]}" -gt 0 ] 2>/dev/null; then
  _EL_RE=$(IFS='|'; printf '%s' "${SECRET_PATTERNS[*]}")
  if printf '%s' "$DETAIL" | grep -qE "$_EL_RE" 2>/dev/null; then
    DETAIL="[redacted — detail matched a secret pattern]"
  fi
fi

# Belt and braces: the ledger's contract is one line per event, and nothing
# above may break it even if a future branch forgets `clean`.
DETAIL=$(printf '%s' "$DETAIL" | tr '\n\r\t' '   ')

printf '%s %s %s\n' "$TIMESTAMP" "$EVENT_TYPE" "$DETAIL" >> "$LOG_FILE"

# Rotate: keep last 500 lines
LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
if [ "$LINES" -gt 500 ]; then
  tail -400 "$LOG_FILE" > "$LOG_FILE.$$.tmp" && mv "$LOG_FILE.$$.tmp" "$LOG_FILE"
fi

exit 0
