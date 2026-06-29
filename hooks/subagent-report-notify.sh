#!/usr/bin/env bash
# Claude Supercharger — Subagent Report Notify
# Event: SubagentStop | Matcher: (none)  [BLOCKING — must inject into parent]
#
# Closes the last gap in the report-recovery story. When a subagent's final
# message comes back DEGRADED (CC #54323 return-channel bug: "Ready.",
# "Standing by.", "[Agent stopped]", "Complete.", etc.), the parent loses the
# findings — and nothing tells it the report was recovered to disk by the async
# subagent-report-fallback.sh. This hook detects the degraded stub and injects an
# additionalContext pointer naming the deterministic report path + the exact
# read command. Must be BLOCKING (not async): async SubagentStop hooks cannot
# inject hookSpecificOutput into the parent's context.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "subagent-report-notify" && exit 0

# v2.7.12: accept subagent_id too (key-drift resilience across CC versions).
AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // .subagent_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$AGENT_ID" ] && exit 0

REPORT_DIR="$HOME/.claude/supercharger/scope/subagent-reports"
REPORT_PATH="$REPORT_DIR/${AGENT_ID}.md"
TOOL="$HOME/.claude/supercharger/tools/subagent-report.sh"

# Is the final message a degraded/truncated stub? Only notify when the parent
# actually lost the findings — a full final message needs no pointer.
IS_DEGRADED=$(AGENT_ID="$AGENT_ID" python3 -c "
import os, sys, json, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

last = (d.get('last_assistant_message') or d.get('result') or d.get('output') or '')
if isinstance(last, list):
    last = ' '.join(str(x.get('text','') if isinstance(x, dict) else x) for x in last)
last = str(last).strip()
# Empty final = degraded by definition.
if not last:
    print('1'); sys.exit(0)

low = last.lower()
stubs = [
    r'^ready\.?$', r'^standing by\.?$', r'^\[agent stopped\]$', r'^\[no user message\.?\]$',
    r'^complete\.?$', r'^completed\.?$', r'^done\.?$', r'^acknowledged\.?$',
    r'^understood\.?$', r'^ok(ay)?\.?$', r'^finished\.?$', r'^task complete[d]?\.?$',
]
if any(re.match(p, low) for p in stubs):
    print('1'); sys.exit(0)
# Very short, no substance (no sentence/markdown/path) — likely truncated.
if len(last) <= 24 and not re.search(r'[/.:]\w|\n', last):
    print('1'); sys.exit(0)
print('0')
" <<<"$_INPUT" 2>/dev/null || echo "0")

[ "$IS_DEGRADED" = "1" ] || exit 0

AGENT_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.agent_name // .agent_type // "subagent"' 2>/dev/null || echo "subagent")

MSG="[SUBAGENT REPORT] ${AGENT_NAME} (agent ${AGENT_ID}) returned a truncated/degraded final message — CC return-channel bug #54323, so its actual findings did NOT come back inline. The full report was recovered to disk. Read it before continuing: bash ${TOOL} ${AGENT_ID}  (or: bash ${TOOL} --latest). Path: ${REPORT_PATH} — if it is not there yet, the async recovery is still writing; retry the command once."

# Dedup: don't re-inject the same pointer twice in a session.
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "subagent-report-notify" "$SESSION_ID" "$AGENT_ID" && exit 0

echo "[Supercharger] subagent-report-notify: degraded final for agent=${AGENT_ID}, pointed parent to report" >&2

CTX=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$MSG")
# additionalContext (not systemMessage): systemMessage on SubagentStop can be
# read by CC as a replacement for the subagent's terminal output.
printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}\n' "$CTX"

exit 0
