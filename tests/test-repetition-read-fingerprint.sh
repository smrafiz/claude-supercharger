#!/usr/bin/env bash
# Suite for repetition-detector.sh Read-fingerprint fix (v2.21.14).
# `read` with IFS=tab collapsed the empty command column for Read tools, so
# file_path shifted into F_CMD and session_id into F_FPATH — the Read
# fingerprint keyed on the SESSION ID, making any 3 reads look like a loop
# (bogus `[LOOP] 'Read:<sid>'`). Now fields are split on \037 (non-whitespace),
# so the fingerprint keys on the file path.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/repetition-detector.sh"

new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }
read_json() { printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"cwd":"/tmp","session_id":"s1"}' "$1"; }
bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"/tmp","session_id":"s1"}' "$1"; }

begin_test "repetition: 3 reads of DIFFERENT files do NOT trigger a loop"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(read_json /a.txt)"
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(read_json /b.txt)"
OUT=$(SUPERCHARGER_STATE="$D" bash "$H" 2>&1 <<<"$(read_json /c.txt)")
echo "$OUT" | grep -q 'LOOP' && fail "distinct reads falsely flagged as a loop: $OUT" || pass
rm -rf "$D"

begin_test "repetition: 3 reads of the SAME file DO trigger a loop (keyed by path)"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(read_json /same.txt)"
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(read_json /same.txt)"
OUT=$(SUPERCHARGER_STATE="$D" bash "$H" 2>&1 <<<"$(read_json /same.txt)")
echo "$OUT" | grep -q "Read:/same.txt" && pass || fail "same-file read loop not detected or wrong key: $OUT"
rm -rf "$D"

begin_test "repetition: Bash loop detection still works (keyed by command)"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(bash_json 'git status')"
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(bash_json 'git status')"
OUT=$(SUPERCHARGER_STATE="$D" bash "$H" 2>&1 <<<"$(bash_json 'git status')")
echo "$OUT" | grep -q "Bash:git status" && pass || fail "bash loop not detected or wrong key: $OUT"
rm -rf "$D"

begin_test "repetition: distinct bash commands do NOT trigger a loop"
D=$(new_state)
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(bash_json 'ls')"
SUPERCHARGER_STATE="$D" bash "$H" >/dev/null 2>&1 <<<"$(bash_json 'pwd')"
OUT=$(SUPERCHARGER_STATE="$D" bash "$H" 2>&1 <<<"$(bash_json 'whoami')")
echo "$OUT" | grep -q 'LOOP' && fail "distinct commands falsely flagged: $OUT" || pass
rm -rf "$D"

report
