#!/usr/bin/env bash
# Stop can fire before the final reply is flushed to the transcript, so the gate also
# judges the Stop payload's last_assistant_message. Transcripts here END at the edit
# result, with no final assistant text, as in the live miss.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# CG_HOOK lets the regression proof point at a pre-change copy of the hook (beside its libs).
GATE="${CG_HOOK:-$REPO_DIR/hooks/claim-evidence-gate.sh}"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
RBP="$TD/rb"; PLAIN="$TD/plain"; mkdir -p "$RBP" "$PLAIN"
printf '| Item | Your value | Example |\n|---|---|---|\n| Targeted test | `make check` | x |\n' > "$RBP/READBACK.md"

python3 - "$TD" <<'PY'
import json, sys
td = sys.argv[1]
def res(tid, text):
    return json.dumps({"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": tid, "is_error": False,
         "content": [{"type": "text", "text": text}]}]}}) + "\n"
edit = json.dumps({"type": "assistant", "message": {"content": [
    {"type": "tool_use", "id": "e1", "name": "Edit",
     "input": {"file_path": "src/add.sh", "old_string": "+", "new_string": "-"}}]}}) + "\n" + res("e1", "ok")
open(td + "/ends_at_edit.jsonl", "w").write(edit)
# the reply IS already in the transcript: the payload copy must not be judged twice
open(td + "/flushed.jsonl", "w").write(edit + json.dumps({"type": "assistant", "message": {"content": [
    {"type": "text", "text": "Done."}]}}) + "\n")
PY

rc() { # transcript, project dir, last_assistant_message, [stop_hook_active]
  python3 -c 'import json,sys;print(json.dumps({"transcript_path":sys.argv[1],"stop_hook_active":sys.argv[4]=="true","last_assistant_message":sys.argv[3]}))' \
    "$TD/$1.jsonl" "$2" "$3" "${4:-false}" | CLAUDE_PROJECT_DIR="$2" bash "$GATE" >/dev/null 2>&1
  echo $?
}

echo "=== Claim Gate last_assistant_message Tests ==="

begin_test "readback: edit, transcript has no final text, payload 'Done.' -> blocks once"
[ "$(rc ends_at_edit "$RBP" "Done.")" = 2 ] && pass || fail "rc=$(rc ends_at_edit "$RBP" "Done.")"

begin_test "readback: the continuation (stop_hook_active) is not blocked again"
[ "$(rc ends_at_edit "$RBP" "Done." true)" = 0 ] && pass || fail "looped"

begin_test "readback: 'not done' in the payload is not a claim"
[ "$(rc ends_at_edit "$RBP" "Not done yet, the fix is not fixed.")" = 0 ] && pass || fail "hedge ignored"

begin_test "no READBACK.md: the same payload does not block"
[ "$(rc ends_at_edit "$PLAIN" "Done.")" = 0 ] && pass || fail "rc=$(rc ends_at_edit "$PLAIN" "Done.")"

begin_test "SUPERCHARGER_CLAIM_READBACK_ARM=0 turns the arm off"
printf '{"transcript_path":"%s","stop_hook_active":false,"last_assistant_message":"Done."}' "$TD/flushed.jsonl" \
  | SUPERCHARGER_CLAIM_READBACK_ARM=0 CLAUDE_PROJECT_DIR="$RBP" bash "$GATE" >/dev/null 2>&1; r=$?
[ "$r" = 0 ] && pass || fail "rc=$r"

begin_test "reply already in the transcript is judged once (still blocks, no error)"
[ "$(rc flushed "$RBP" "Done.")" = 2 ] && pass || fail "rc=$(rc flushed "$RBP" "Done.")"

begin_test "a payload with no claim does not block"
[ "$(rc ends_at_edit "$RBP" "Looking at the file now.")" = 0 ] && pass || fail "rc=$(rc ends_at_edit "$RBP" "Looking at the file now.")"

begin_test "non-readback: a pass claim in the payload with no run is advisory, not a block"
[ "$(rc ends_at_edit "$PLAIN" "All tests pass.")" = 0 ] && pass || fail "blocked"

report
