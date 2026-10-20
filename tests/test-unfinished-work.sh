#!/usr/bin/env bash
# unfinished-work: a session that ends with background tasks or scheduled wakeups
# still in flight is named at the next session start in that project. 2026-10-20: a
# release job died in a reboot and nothing said so.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/unfinished-work.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
ST="$TD/state"; mkdir -p "$ST/scope" "$TD/proj" "$TD/other"
A=aaaaaaaa-1111-2222-3333-444444444444
B=bbbbbbbb-1111-2222-3333-444444444444
fire() { SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null; }
stop() { # sid cwd tasks-json crons-json
  printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s","background_tasks":%s,"session_crons":%s}' "$1" "$2" "$3" "$4" | fire; }
start() { # sid cwd [source]
  printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s","source":"%s"}' "$1" "$2" "${3:-startup}" | fire; }
TASK='[{"id":"t1","type":"shell","status":"running","description":"Release job 4.3.24"}]'
CRON='[{"id":"c1","schedule":"*/5 * * * *","recurring":true,"prompt":"check CI"}]'

echo "=== Unfinished Work Tests ==="

begin_test "unfinished: Stop with running work writes a snapshot"
stop "$A" "$TD/proj" "$TASK" '[]'
[ -f "$ST/scope/.inflight-$A.json" ] && pass || fail "no snapshot"

begin_test "unfinished: the next session in the project names it"
OUT=$(start "$B" "$TD/proj")
printf '%s' "$OUT" | grep -q 'Release job 4.3.24' && printf '%s' "$OUT" | grep -q UNFINISHED && pass || fail "got: $OUT"

begin_test "unfinished: named once, not on every start"
OUT=$(start "$B" "$TD/proj")
[ -z "$OUT" ] && pass || fail "repeated: $OUT"

begin_test "unfinished: a later Stop with nothing running clears the snapshot"
stop "$A" "$TD/proj" "$TASK" '[]'
stop "$A" "$TD/proj" '[]' '[]'
[ ! -f "$ST/scope/.inflight-$A.json" ] && [ -z "$(start "$B" "$TD/proj")" ] && pass || fail "snapshot survived a clean Stop"

begin_test "unfinished: scheduled wakeups are named too"
stop "$A" "$TD/proj" '[]' "$CRON"
OUT=$(start "$B" "$TD/proj")
printf '%s' "$OUT" | grep -q 'check CI' && pass || fail "got: $OUT"

begin_test "unfinished: another project's snapshot is not shown here"
stop "$A" "$TD/other" "$TASK" '[]'
OUT=$(start "$B" "$TD/proj")
[ -z "$OUT" ] && pass || fail "leaked across projects: $OUT"
rm -f "$ST/scope/.inflight-$A.json"

begin_test "unfinished: a fresh start of the same session does not report itself"
stop "$A" "$TD/proj" "$TASK" '[]'
OUT=$(start "$A" "$TD/proj" startup)
[ -z "$OUT" ] && pass || fail "self-report: $OUT"

begin_test "unfinished: resuming that session after it died does report it"
OUT=$(start "$A" "$TD/proj" resume)
printf '%s' "$OUT" | grep -q 'Release job' && pass || fail "got: $OUT"

begin_test "unfinished: output is valid hook JSON"
stop "$A" "$TD/proj" "$TASK" '[]'
start "$B" "$TD/proj" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="SessionStart"' \
  && pass || fail "bad JSON"

begin_test "unfinished: a payload past the argument limit still works"
BIG=$(python3 -c 'print("x"*400000)')
printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s","last_assistant_message":"%s","background_tasks":%s,"session_crons":[]}' "$A" "$TD/proj" "$BIG" "$TASK" | fire
[ -f "$ST/scope/.inflight-$A.json" ] && pass || fail "big payload dropped"

begin_test "unfinished: registered async on Stop and on SessionStart"
jq -e '([.hooks.Stop[].hooks[]|select(.command|test("unfinished-work"))|.async]==[true])
  and ([.hooks.SessionStart[].hooks[]|select(.command|test("unfinished-work"))]|length==1)' "$REPO_DIR/hooks/hooks.json" >/dev/null \
  && pass || fail "registration"

report
