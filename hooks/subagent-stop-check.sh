#!/usr/bin/env bash
# Claude Supercharger — SubagentStop Completion Check
# Event: SubagentStop | Matcher: (none)
# Reads last_assistant_message from subagent output and flags incomplete/failed work
# to the parent session. Advisory — does not block, injects systemMessage.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "subagent-stop-check" && exit 0
hook_profile_skip "subagent-stop-check" && exit 0

MSG=$(printf '%s\n' "$_INPUT" | python3 -c "
import os, sys, json, re

TIER = os.environ.get('SUPERCHARGER_TIER', 'standard')

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

last_msg = (d.get('last_assistant_message') or '').strip()
if not last_msg:
    sys.exit(0)

agent_name = (d.get('agent_name') or d.get('agent_type') or 'subagent').strip()
msg_lower = last_msg.lower()

# Failure patterns
failure_patterns = [
    (r\"i (couldn't|could not|was unable to|cannot|can't)\", 'reported inability'),
    (r'(failed to|failure|error occurred|threw an? (error|exception))', 'reported failure'),
    (r\"i don't have (access|permission|the ability)\", 'reported access issue'),
    (r'(not (found|available|accessible|supported))', 'resource not found'),
]

# Incomplete patterns (case-sensitive for TODO/FIXME, lowercase for rest)
incomplete_patterns_cs = [
    (r'(TODO|FIXME)', 'left work incomplete'),
]
incomplete_patterns = [
    (r'(not (yet )?implemented|placeholder)', 'left work incomplete'),
    (r'(would need to|you (would|should|could|may want to)|consider (also|adding|doing))', 'deferred work to you'),
    (r'(i stopped|i halted|i paused|i did not (finish|complete))', 'did not finish'),
]

findings = []
for pattern, label in failure_patterns:
    if re.search(pattern, msg_lower):
        findings.append(label)
        break

for pattern, label in incomplete_patterns_cs:
    if re.search(pattern, last_msg):
        findings.append(label)
        break

if not findings:
    for pattern, label in incomplete_patterns:
        if re.search(pattern, msg_lower):
            findings.append(label)
            break

if not findings:
    sys.exit(0)

labels = ', '.join(findings)
if TIER == 'minimal':
    print(f'[review] {agent_name}: {labels}')
elif TIER == 'lean':
    summary = last_msg[:80].replace(chr(10), ' ')
    print(f'[Subagent] {agent_name} — {labels}. \"{summary}\"')
else:
    summary = last_msg[:200].replace(chr(10), ' ')
    print(f'[Subagent review] {agent_name} {labels}. Last message: \"{summary}\". Review output and determine if follow-up is needed.')
" 2>/dev/null)

[ -z "$MSG" ] && exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
hook_already_emitted "subagent-stop-check" "$SESSION_ID" "$MSG" && exit 0

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"

exit 0
