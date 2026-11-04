#!/usr/bin/env bash
# Claude Supercharger — Agent Handoff Gate
# Event: PreToolUse | Matcher: SubagentHandback  (also SubagentStop, older Claude Code)
# Validates sub-agent output quality before the result flows back to the parent.
# On SubagentHandback it refuses the first flagged report once, so the subagent itself
# fixes or confirms it. Measured CC 2.1.318: subagents end through that tool call, and a
# SubagentStop note (additionalContext, systemMessage or exit 2) reaches nobody.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# Extract agent output text
AGENT_OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # v2.7.12: CC's SubagentStop payload carries the agent's final text in
    # last_assistant_message — the older result/output/content keys are absent,
    # so this gate saw empty output and never fired. Try the real key first.
    out = (d.get('tool_input') or {}).get('message') or d.get('last_assistant_message') or d.get('result') or d.get('output') or d.get('content') or ''
    if isinstance(out, list):
        out = ' '.join(str(x.get('text','') if isinstance(x,dict) else x) for x in out)
    print(str(out)[:4000])
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$AGENT_OUTPUT" ] && exit 0

AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")

# Score output quality — look for failure signals
QUALITY_ISSUE=$(python3 -c "
import re, sys

output = sys.argv[1].lower()

# Incomplete work signals
incomplete = [
    r'\btodo\b', r'\bfixme\b', r'\bnot implemented\b', r'\bstub\b',
    r'\bpass\s*#', r'\b\.\.\.\s*$', r'placeholder',
    r'i (was unable|could not|cannot|am unable) to',
    r'(failed|error|exception) (to|while|when)',
    r'\bleft as an exercise\b',
    r'i (stopped|halted|did not (finish|complete))',
]
# Uncertainty signals that should trigger a check
uncertain = [
    r'i (think|believe|assume) (this|it) (should|might|may|could)',
    r'(should|might) work', r'(probably|likely) (correct|fine|ok)',
    r'i (haven.t|have not) (tested|verified|confirmed)',
]

for pattern in incomplete:
    if re.search(pattern, output):
        print('incomplete')
        sys.exit(0)

count = sum(1 for p in uncertain if re.search(p, output))
if count >= 2:
    print('unverified')
    sys.exit(0)

print('')
" "$AGENT_OUTPUT" 2>/dev/null || echo "")

[ -z "$QUALITY_ISSUE" ] && exit 0

if [ "$QUALITY_ISSUE" = "incomplete" ]; then
  MSG="[AGENT-GATE] Sub-agent output contains incomplete work signals (TODO, stub, unimplemented, or explicit failure). Verify the result before proceeding — do not silently accept partial output."
else
  MSG="[AGENT-GATE] Sub-agent output contains multiple unverified claims (\"should work\", \"probably correct\", \"haven't tested\"). Treat this output with skepticism and verify key assertions before continuing."
fi

echo "[Supercharger] agent-handoff-gate: quality issue detected (${QUALITY_ISSUE}) for agent=${AGENT_ID}" >&2

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# SubagentHandback: refuse once per agent, so a revised report always goes through.
if [ "$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "SubagentHandback" ]; then
  # A marker per (session, agent), not the 600s dedup: a long revision must not be refused twice.
  _HB_MARK="$SUPERCHARGER_STATE/scope/.handback-refused-$(printf '%s' "${SESSION_ID:-default}-${AGENT_ID:-none}" | tr -c 'A-Za-z0-9_-' '_')"
  [ -e "$_HB_MARK" ] && exit 0
  mkdir -p "${_HB_MARK%/*}" 2>/dev/null; : > "$_HB_MARK" 2>/dev/null || exit 0
  . "$HOOKS_DIR/lib-deny.sh"
  if [ "$QUALITY_ISSUE" = "incomplete" ]; then
    WHY="your report mentions unfinished work (TODO, stub, not implemented, or a failure)."
  else
    WHY="your report makes claims you say you have not checked (\"should work\", \"probably correct\", \"haven't tested\")."
  fi
  sc_deny "handoff paused once: $WHY" "finish or verify what you can, then call SubagentHandback again with a report that says plainly what is done and what is not. If the report is already accurate, send it again unchanged; this check will not stop it twice."
fi

# v2.7.29: SubagentStop re-fires ~10x with stop_hook_active — without a dedup the
# parent received the same [AGENT-GATE] injection up to 10 times per stop. Guard
# with the shared once-per-(session,message) latch in lib-suppress.sh.
hook_already_emitted "agent-handoff-gate" "$SESSION_ID" "$MSG" && exit 0

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null) || exit 0

# Always use additionalContext on SubagentStop — systemMessage in this event
# can be interpreted by Claude Code as a replacement for the subagent's
# terminal message, swallowing the actual findings.
printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
