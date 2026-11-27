#!/usr/bin/env bash
# claim-evidence-gate, readback arm: only when READBACK.md is at the project root, a
# declared gate command counts as a test run, a bare "done" / "is fixed" is a claim, and
# code edited this turn with no test or gate run after it blocks once. A project
# without READBACK.md is unchanged.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# CG_HOOK lets the regression proof point at a pre-change copy of the hook (beside its libs).
GATE="${CG_HOOK:-$REPO_DIR/hooks/claim-evidence-gate.sh}"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
RBP="$TD/rb"; PLAIN="$TD/plain"; mkdir -p "$RBP" "$PLAIN"
cat > "$RBP/READBACK.md" <<'EOF'
| Item | Your value | Example |
|---|---|---|
| Targeted test | `make check` | x |
EOF

mk() { # name, python expression building the transcript from asst/ed/res
  python3 - "$TD/$1.jsonl" "$2" <<'PY'
import json, sys
out, spec = sys.argv[1], sys.argv[2]
def asst(text=None, cmd=None, tid=None):
    c = []
    if text is not None: c.append({"type": "text", "text": text})
    if cmd: c.append({"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}})
    return json.dumps({"type": "assistant", "message": {"content": c}}) + "\n"
def res(tid, text, err=False):
    return json.dumps({"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": tid, "is_error": err,
         "content": [{"type": "text", "text": text}]}]}}) + "\n"
def ed(path, tid="e1"):
    return json.dumps({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": tid, "name": "Edit",
         "input": {"file_path": path, "old_string": "a", "new_string": "b"}}]}}) + "\n" + res(tid, "ok")
open(out, "w").write(eval(spec))
PY
}
rc() { # transcript, project dir [, stop_hook_active]
  printf '{"transcript_path":"%s","stop_hook_active":%s}' "$TD/$1.jsonl" "${3:-false}" \
    | CLAUDE_PROJECT_DIR="$2" bash "$GATE" >/dev/null 2>&1
  echo $?
}

echo "=== Claim Gate Readback Arm Tests ==="

mk done_edit 'ed("src/a.py") + asst(text="All done.")'
begin_test "readback: code edited, 'All done.', no run -> blocks once"
[ "$(rc done_edit "$RBP")" = 2 ] && pass || fail "rc=$(rc done_edit "$RBP")"

begin_test "readback: the continuation (stop_hook_active) is not blocked again"
[ "$(rc done_edit "$RBP" true)" = 0 ] && pass || fail "looped"

begin_test "no READBACK.md: same transcript is unchanged (no block)"
[ "$(rc done_edit "$PLAIN")" = 0 ] && pass || fail "rc=$(rc done_edit "$PLAIN")"

mk fixed_edit 'ed("src/a.py") + asst(text="The parser bug is now fixed.")'
begin_test "readback: 'is now fixed' after a code edit blocks"
[ "$(rc fixed_edit "$RBP")" = 2 ] && pass || fail "rc=$(rc fixed_edit "$RBP")"

mk not_done 'ed("src/a.py") + asst(text="Not done yet, the fix is not fixed for Windows.")'
begin_test "readback: 'not done' / 'not fixed' is not a claim"
[ "$(rc not_done "$RBP")" = 0 ] && pass || fail "hedge ignored"

mk prose_edit 'ed("README.md") + asst(text="All done.")'
begin_test "readback: a prose-only edit does not block"
[ "$(rc prose_edit "$RBP")" = 0 ] && pass || fail "rc=$(rc prose_edit "$RBP")"

mk gate_ok 'ed("src/a.py") + asst(cmd="make check", tid="g1") + res("g1", "12 passed") + asst(text="All done.")'
begin_test "readback: a gate run after the edit clears it"
[ "$(rc gate_ok "$RBP")" = 0 ] && pass || fail "rc=$(rc gate_ok "$RBP")"

mk gate_stale 'asst(cmd="make check", tid="g1") + res("g1", "12 passed") + ed("src/a.py") + asst(text="All done.")'
begin_test "readback: a gate run BEFORE the edit does not clear it"
[ "$(rc gate_stale "$RBP")" = 2 ] && pass || fail "rc=$(rc gate_stale "$RBP")"

mk gate_fail 'asst(cmd="make check", tid="g1") + res("g1", "1 failed\nFAIL: x", err=True) + asst(text="All tests pass.")'
begin_test "readback: a failing gate run contradicts a pass claim"
[ "$(rc gate_fail "$RBP")" = 2 ] && pass || fail "rc=$(rc gate_fail "$RBP")"
begin_test "no READBACK.md: the same failing 'make check' is not a test run"
[ "$(rc gate_fail "$PLAIN")" = 0 ] && pass || fail "rc=$(rc gate_fail "$PLAIN")"

report
