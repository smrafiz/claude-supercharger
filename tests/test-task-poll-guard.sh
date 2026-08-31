#!/usr/bin/env bash
# Suite for task-poll-guard.sh (v4.0.5).
#
# The harness re-invokes the session when a background task exits and the
# notification carries the output path, so sleeping on that file buys time the
# agent already has. Measured before the guard was written: 245 such commands
# across 8 sessions in this project's own transcripts. The harness already
# printed an advisory saying not to chain sleeps; nothing enforced it.
#
# The NEGATIVES are the load-bearing half here, in two directions:
#   1. a legitimate wait on something the harness does NOT track (CI, a deploy,
#      a port, a lock) must pass — that is the normal use of sleep
#   2. the pattern quoted as DATA must pass — a heredoc, an interpreter -c
#      string, an echo, a grep over transcripts. A guard that cannot tell a
#      command from a mention of a command denies the tests written for it, and
#      this repo has blocked its own probes that way more than once.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/task-poll-guard.sh"
# Assembled so this file's own text is not a literal the guard would match if a
# future maintainer ran the suite through something that inspects commands.
TASKF="/private/tmp/proj/ses/tasks/bk93ax.output"

echo "=== task-poll-guard ==="

_verdict() {  # $1 = command, $2 = optional session id -> deny|allow
  local d out
  d=$(mktemp -d)
  out=$(printf '{"session_id":"%s","cwd":"/tmp","tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":%s}}' \
        "${2:-s$RANDOM}" "$(P="$1" python3 -c 'import json,os;print(json.dumps(os.environ["P"]))')" \
        | SUPERCHARGER_STATE="$d" bash "$HOOK" 2>/dev/null)
  rm -rf "$d"
  case "$out" in *'"deny"'*) echo deny ;; *) echo allow ;; esac
}

while IFS='|' read -r CMD WANT; do
  [ -z "$CMD" ] && continue
  case "$CMD" in \#*) continue ;; esac
  CMD=${CMD//@T@/$TASKF}
  begin_test "poll: ${CMD:0:56} -> $WANT"
  GOT=$(_verdict "$CMD")
  [ "$GOT" = "$WANT" ] && pass || fail "got $GOT, wanted $WANT"
done <<'CASES'
# --- the shapes that waste the wait ---
until [ -s @T@ ]; do sleep 20; done|deny
while ! grep -q done @T@; do sleep 15; done|deny
sleep 180; cat @T@|deny
sleep 30 && cat @T@|deny
# --- legitimate waits on things the harness does NOT track ---
sleep 5|allow
sleep 2; curl -sf localhost:3000|allow
until curl -sf localhost:3000; do sleep 2; done|allow
gh run watch 33312568102|allow
until [ -f /tmp/deploy.lock ]; do sleep 5; done|allow
# --- reading the task file without waiting on it ---
cat @T@|allow
tail -20 @T@|allow
grep -c PASS @T@|allow
# --- the pattern as DATA, not as the command ---
echo 'until [ -s @T@ ]; do sleep 20; done' > note.txt|allow
printf 'sleep 60; cat @T@' >> doc.md|allow
grep -rn 'sleep' @T@|allow
CASES

begin_test "poll: fires only ONCE per session, then steps aside"
# A guard that cannot be got past becomes a reason to disable the harness. The
# first offender is denied with the explanation; a second attempt goes through.
SID="once$RANDOM"
D=$(mktemp -d)
_twice() {
  printf '{"session_id":"%s","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"until [ -s %s ]; do sleep 9; done"}}' "$SID" "$TASKF" \
    | SUPERCHARGER_STATE="$D" bash "$HOOK" 2>/dev/null
}
FIRST=$(_twice); SECOND=$(_twice)
case "$FIRST" in *'"deny"'*) case "$SECOND" in *'"deny"'*) fail "denied twice in one session" ;; *) pass ;; esac ;;
  *) fail "did not deny the first attempt" ;; esac
rm -rf "$D"

begin_test "poll: kill switch silences it"
D=$(mktemp -d)
OUT=$(printf '{"session_id":"ks","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"until [ -s %s ]; do sleep 9; done"}}' "$TASKF" \
  | SUPERCHARGER_TASK_POLL_GUARD=0 SUPERCHARGER_STATE="$D" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch did not silence it"
rm -rf "$D"

begin_test "poll: PowerShell Start-Sleep is recognised on the channel it registers for"
# Registered for Bash,Monitor,PowerShell. A guard registered for a channel whose
# syntax it cannot read is registered in name only.
[ "$(_verdict "Start-Sleep -Seconds 20; Get-Content $TASKF")" = "deny" ] \
  && pass || fail "Start-Sleep form not caught"

begin_test "poll: registered on PreToolUse for all three shell channels"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
hit = [e for e in d['hooks'].get('PreToolUse', [])
       for h in e.get('hooks', []) if 'task-poll-guard' in h.get('command','')]
assert hit, 'not registered'
m = hit[0].get('matcher','')
for ch in ('Bash','Monitor','PowerShell'):
    assert ch in m, 'missing channel ' + ch
" "$REPO_DIR/hooks/hooks.json" && pass || fail "registration or matcher wrong"

begin_test "poll: sweeps its OWN stale markers and nothing else"
# One marker per session that trips the guard, and a crashed session never runs
# cleanup — so the next firing is the only reliable moment. The sweep is bounded
# to this hook's prefix; a guard that garbage-collects another hook's state is a
# far worse bug than the leak it fixes.
D=$(mktemp -d); mkdir -p "$D/scope"
mkdir -p "$D/scope/.task-poll-warned-stale" "$D/scope/.task-poll-warned-fresh" "$D/scope/.other-hook-marker"
touch -t 202501010000 "$D/scope/.task-poll-warned-stale" "$D/scope/.other-hook-marker" 2>/dev/null
printf '{"session_id":"gc","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"until [ -s /x/tasks/a.output ]; do sleep 9; done"}}' \
  | SUPERCHARGER_STATE="$D" bash "$HOOK" >/dev/null 2>&1
if [ ! -d "$D/scope/.task-poll-warned-stale" ] \
   && [ -d "$D/scope/.task-poll-warned-fresh" ] \
   && [ -d "$D/scope/.other-hook-marker" ]; then pass
else fail "sweep removed the wrong thing (stale kept, fresh gone, or foreign marker touched)"; fi
rm -rf "$D"

report
