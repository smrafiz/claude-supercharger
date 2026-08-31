#!/usr/bin/env bash
# Claude Supercharger — Task Poll Guard
# Event: PreToolUse | Matcher: Bash
#
# Deny a command that both SLEEPS and names a harness task output file. That is
# the shape of `until [ -s .../tasks/<id>.output ]; do sleep 20; done`, of
# `while ! grep -q done .../tasks/x.output; do sleep 15; done`, and of
# `sleep 180; cat .../tasks/x.output`.
#
# The harness re-invokes the session when a background task exits, and the
# notification carries the output path. Sleeping on it buys time you already
# have, and it is worse than doing nothing in three measurable ways:
#
#   - the poll is bounded by the Bash TIMEOUT, not by the job. A wait that hits
#     the ceiling returns empty, having watched a job that exited minutes before.
#   - `sleep 180; cat ...` pays the full 180s even when the job took 12.
#   - piping the polled output through `tail` throws away the head of the log,
#     which is usually where the summary line is.
#
# Measured before writing this: 245 such commands across 8 sessions in this
# project's own transcripts. The harness already prints an advisory telling the
# agent not to chain sleeps; nothing enforced it, and a rule with no mechanism is
# the definition of a hook candidate.
#
# SCOPE IS DELIBERATELY NARROW. Sleeping on something the harness does NOT track
# is the legitimate use and passes untouched: a CI run, a deploy, a port coming
# up, a lock file, a rate limit. Only a task file the harness itself created and
# is already watching trips this.
#
# Fires ONCE per session. The first offender is denied with the explanation; if
# the agent has a reason to insist, the second attempt goes through. A guard that
# cannot be got past turns into a reason to disable the whole harness.
#
# Disable: SUPERCHARGER_TASK_POLL_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TASK_POLL_GUARD:-1}" = "0" ] && exit 0

IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""
_INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Cheap gate: both words must appear somewhere before anything is parsed.
# Case-INSENSITIVE on the sleep half. PowerShell spells it `Start-Sleep`, which
# contains "Sleep" and not "sleep", so a case-sensitive gate silently swallowed
# every PowerShell poll while the detector below matched it perfectly — the rule
# present and unreachable, which is the failure mode that looks like success.
# This gate must stay a SUPERSET of what the checks below look for.
case "$_INPUT" in *[sS][lL][eE][eE][pP]*) ;; *) exit 0 ;; esac
case "$_INPUT" in *tasks/*) ;; *) exit 0 ;; esac

CMD=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
[ -z "$CMD" ] && exit 0

FLAT=$(printf '%s' "$CMD" | tr '\n' ' ')

# The pattern as DATA, not as the command being run. A heredoc, an interpreter
# -c string, an echo, a grep over transcripts: all MENTION the shape without
# waiting on anything. A guard that cannot tell the difference denies the tests
# written for it — this repo has blocked its own probes that way more than once.
printf '%s' "$FLAT" | grep -Eq "<<-?[[:space:]]*['\"]?[A-Za-z_]+" && exit 0
printf '%s' "$FLAT" | grep -Eq '(python3?|node|perl|ruby)[[:space:]]+-[ce][[:space:]]' && exit 0
printf '%s' "$FLAT" | grep -Eq '^[[:space:]]*(echo|printf|grep|rg|cat)([[:space:]]|$)' && exit 0

# BOTH halves required: a wait on a clock, and a harness task file.
# Start-Sleep is PowerShell's spelling. This hook is registered for the
# PowerShell channel alongside Bash and Monitor, and a guard registered for a
# channel whose syntax it cannot read is registered in name only — the parity
# drift this repo has fixed several times.
printf '%s' "$FLAT" | grep -Eiq '(^|[;&|( ])(sleep[[:space:]]+[0-9.]|start-sleep([[:space:]]+-[a-z]+)*[[:space:]]+[0-9.])' || exit 0
printf '%s' "$FLAT" | grep -Eq '/tasks/[A-Za-z0-9_-]+\.output' || exit 0

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
STATE_DIR="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope"
mkdir -p "$STATE_DIR" 2>/dev/null || true
MARK="$STATE_DIR/.task-poll-warned-$SESSION_ID"

# Already fired this session: step aside. mkdir is the claim — one syscall, so
# two writers in the same turn cannot both pass the check and both deny.
if ! mkdir "$MARK" 2>/dev/null; then
  exit 0
fi

REASON="You don't need to wait for that — background tasks wake you when they exit, and the notification carries the output path.

Launch it and do something else: read the file you're about to change, write the next script, answer the question you're holding.

Polling is worse than doing nothing, in three ways this project measured on itself:
  - the poll is bounded by the Bash timeout, not by the job, so a wait that hits the ceiling returns empty having watched a job that finished minutes earlier
  - 'sleep 180; cat ...' pays the full 180s even when the job took 12
  - piping the polled output through 'tail' discards the head of the log, which is usually where the summary is

If the very next thing you do genuinely depends on it and nothing else can happen first, say so and run it in the FOREGROUND — that is honest, and it is bounded by the job rather than by a clock.

Sleeping on something the harness does not track is fine and this guard ignores it: a CI run, a deploy, a port coming up, a lock file. It only stops you polling a task file the harness created for you and is already watching.

This fires once per session; if you have a reason to insist, run it again."

REASON_JSON=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null) || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$REASON_JSON"
exit 0
