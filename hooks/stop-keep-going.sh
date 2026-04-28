#!/usr/bin/env bash
# Claude Supercharger — Stop Keep-Going Nudge
# Event: Stop | Matcher: (none)
# Activation: opt-in only — touch ~/.claude/supercharger/scope/.keep-going
#             or set SUPERCHARGER_KEEP_GOING=1
# Detects when Claude stops asking the user to confirm next steps mid-task,
# and nudges it to continue instead of waiting. Conservative: only blocks
# stops that clearly defer work back to the user without delivering.
# Capped at 3 nudges per session.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "stop-keep-going" && exit 0
hook_profile_skip "stop-keep-going" && exit 0

# Disabled by default — opt-in via .supercharger.json or env
KEEP_GOING_FLAG="$HOME/.claude/supercharger/scope/.keep-going"
[ ! -f "$KEEP_GOING_FLAG" ] && [ "${SUPERCHARGER_KEEP_GOING:-0}" != "1" ] && exit 0

# Cap pokes per session to avoid loops
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "default")
POKE_LOG="$HOME/.claude/supercharger/scope/.keep-going-${SESSION_ID}"
POKE_COUNT=0
[ -f "$POKE_LOG" ] && POKE_COUNT=$(wc -l < "$POKE_LOG" 2>/dev/null | tr -d ' ' || echo 0)
[ "$POKE_COUNT" -ge 3 ] && exit 0

REASON=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

last_msg = (d.get('last_assistant_message') or '').strip()
if not last_msg or len(last_msg) < 20:
    sys.exit(0)

msg_lower = last_msg.lower()

# Defer patterns checked FIRST — these override partial-completion language.
defer_patterns = [
    (r'\bshould i (continue|proceed|go ahead|do that|start)', 'asked confirmation to continue'),
    (r'\b(want|would you like) me to\b', 'asked permission for next step'),
    (r'\blet me know (if|when|whether)\b', 'awaited user direction'),
    (r'\bi can (also|next|then|now)\b', 'offered but did not execute'),
    (r'\bnext,? i (would|will|can|could)\b', 'described next step without doing it'),
    (r'\bshall i\b', 'asked confirmation'),
    (r'\bproceed\?$|continue\?$|next\?$', 'ended with question'),
]

# Strong conclusive endings — only skip if no defer pattern matched.
conclusive_patterns = [
    r'\ball tests pass',
    r'\bready (for|to) (review|merge|deploy)',
    r'\b(shipped|merged|released|deployed)\b',
    r'\bsuccessfully\b.*\.\s*$',
]

for pattern, label in defer_patterns:
    if re.search(pattern, msg_lower):
        print(label)
        sys.exit(0)

for p in conclusive_patterns:
    if re.search(p, msg_lower):
        sys.exit(0)
" 2>/dev/null)

[ -z "$REASON" ] && exit 0

# Log the poke for cap tracking
mkdir -p "$(dirname "$POKE_LOG")" 2>/dev/null || true
date -u +"%Y-%m-%dT%H:%M:%SZ" >> "$POKE_LOG" 2>/dev/null || true

NUDGE="The previous response ${REASON} instead of completing the work. Continue with the next step now without asking — proceed if the action is reversible/safe, or surface a specific blocker if not."

REASON_JSON=$(printf '%s' "$NUDGE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"decision":"block","reason":%s}\n' "$REASON_JSON"
echo "[Supercharger] stop-keep-going: nudged Claude (${REASON})" >&2

exit 0
