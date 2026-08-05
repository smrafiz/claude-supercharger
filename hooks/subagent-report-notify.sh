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
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "subagent-report-notify" && exit 0

# v2.7.12: accept subagent_id too (key-drift resilience across CC versions).
AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // .subagent_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$AGENT_ID" ] && exit 0

REPORT_DIR="$SUPERCHARGER_STATE/scope/subagent-reports"
REPORT_PATH="$REPORT_DIR/${AGENT_ID}.md"
TOOL="$SUPERCHARGER_HOME/tools/subagent-report.sh"

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
# Meta-notes: the agent talks ABOUT its report/return channel instead of giving
# findings (e.g. 'findings delivered inline', 'no further action', 'not writing
# the recovery file'). These are short and evade the stub list, so the parent
# silently loses the findings. Treat as degraded when short and substance-free.
meta = [
    'delivered inline', 'no further action', 'returning inline', 'not writing',
    'already delivered', 'see my earlier', 'see above', 'nothing to retry',
    'report .md', 'report file', 'findings above', 'findings below',
    'inline and complete', 'intact', 'no recovery file',
]
if len(last) < 400 and any(p in low for p in meta):
    print('1'); sys.exit(0)
# Very short, no substance (no sentence/markdown/path) — likely truncated.
if len(last) <= 24 and not re.search(r'[/.:]\w|\n', last):
    print('1'); sys.exit(0)
print('0')
" <<<"$_INPUT" 2>/dev/null || echo "0")

[ "$IS_DEGRADED" = "1" ] || exit 0

AGENT_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.agent_name // .agent_type // "subagent"' 2>/dev/null || echo "subagent")

# v2.19.1: if the async fallback (subagent-report-fallback.sh) has already written
# the report, INLINE its tail — the findings are the agent's last substantive block,
# so the tail carries the deliverable — and the parent gets them WITHOUT running a
# recovery command. If the report isn't on disk yet (the async scraper races this
# blocking hook), fall back to the pointer + retry hint. The inline is capped so a
# large fan-out can't flood context; the full report is always one command away.
_INLINE_CAP="${SUPERCHARGER_SUBAGENT_INLINE_CAP:-2000}"
if [ -s "$REPORT_PATH" ]; then
  _FINDINGS=$(tail -c "$_INLINE_CAP" "$REPORT_PATH" 2>/dev/null || true)
  MSG="[SUBAGENT REPORT] ${AGENT_NAME} (agent ${AGENT_ID}) returned a degraded final message (CC return-channel bug #54323) — its findings did NOT come back inline. Recovered from the transcript below (tail, last ${_INLINE_CAP} chars; full report: bash ${TOOL} ${AGENT_ID}):
────────
${_FINDINGS}
────────"
else
  MSG="[SUBAGENT REPORT] ${AGENT_NAME} (agent ${AGENT_ID}) returned a truncated/degraded final message — CC return-channel bug #54323, so its actual findings did NOT come back inline. The full report was recovered to disk. Read it before continuing: bash ${TOOL} ${AGENT_ID}  (or: bash ${TOOL} --latest). Path: ${REPORT_PATH} — if it is not there yet, the async recovery is still writing; retry the command once."
fi

# Dedup: don't re-inject the same pointer twice in a session.
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")

# v2.26.54: record the pointer to a file BEFORE the dedup check and before
# emitting, for two reasons that turned out to be the same fix.
#
# 1. A CHANNEL THAT DOES NOT DEPEND ON THE UNCERTAIN ONE. This hook's whole
#    design assumes Claude Code delivers `additionalContext` from a SubagentStop
#    hook into the parent's context. Reported twice from the field: the report
#    WAS recovered to disk, and the parent still said "verifying the files
#    directly" — the behaviour you would see if the pointer never arrived. Until
#    that is settled, `/why` reads this file, so the path is always reachable.
#
# 2. INSTRUMENTATION. Nothing recorded whether this hook fired, so "did it not
#    run?" and "did it run and CC discard the context?" were indistinguishable.
#    An entry here means it ran. Absence after a degraded subagent means it did
#    not — which is a different bug with a different fix.
#
# Written before the dedup exit on purpose: the second firing for the same agent
# is exactly the evidence that would otherwise be missing.
_SR_SCOPE="$SUPERCHARGER_STATE/scope"
mkdir -p "$_SR_SCOPE" 2>/dev/null || true
_SR_F="$_SR_SCOPE/.subagent-report-${SESSION_ID}"
{
  printf '[%s] %s (agent %s) returned a degraded final; report: %s\n' \
    "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)" \
    "$AGENT_NAME" "$AGENT_ID" "$REPORT_PATH"
} >> "$_SR_F" 2>/dev/null || true
# Bound it — a large fan-out of degraded agents must not grow this without limit.
if [ "$(wc -l < "$_SR_F" 2>/dev/null | tr -d ' ' || echo 0)" -gt 200 ]; then
  tail -n 100 "$_SR_F" > "$_SR_F.tmp" 2>/dev/null && mv "$_SR_F.tmp" "$_SR_F" 2>/dev/null || true
fi

hook_already_emitted "subagent-report-notify" "$SESSION_ID" "$AGENT_ID" && exit 0

echo "[Supercharger] subagent-report-notify: degraded final for agent=${AGENT_ID}, pointed parent to report" >&2

CTX=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$MSG")

# v2.26.55: emit BOTH channels. They are complementary, not alternatives — the
# earlier note here treated them as a choice and picked one, which is why the
# user saw nothing but "Ready.".
#
#   additionalContext -> enters CLAUDE's context (the parent can act on it)
#   systemMessage     -> reaches the USER only  (v2.7.31 established this in
#                        session-memory-inject: "systemMessage only reached the
#                        USER, so the memory never entered Claude's context")
#
# Sending only additionalContext meant the findings were, at best, available to
# the model and invisible to the person watching a subagent return a stub.
#
# The original objection — systemMessage on SubagentStop may be rendered in
# place of the subagent's terminal output — is the DESIRED behaviour here: this
# hook only fires when that output is a degraded stub, so there is nothing worth
# preserving. Replacing "Ready." with the recovered findings is the point.
# Both channels carry the SAME text, which already inlines the recovered
# findings when the report is on disk (see the $MSG construction above). The
# user-facing copy deliberately carries the findings rather than only a path —
# a pointer asks the reader to run a command to see work that already exists.
printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}\n' "$CTX" "$CTX"

exit 0
