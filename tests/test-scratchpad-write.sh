#!/usr/bin/env bash
# Harness scratchpad writes via the Write tool (v2.26.66)
#
# Claude Code's system prompt directs ALL temporary files to a per-session
# scratchpad under the OS temp dir. path-guard's abs-path rule denied that path for
# the Write tool while the identical path succeeded through Bash — so scratch work
# got written into the project tree instead, the exact outcome the rule exists to
# prevent. Same class as v2.8.11, which carved out Claude Code's file-memory store
# after `/remember` silently failed for the same reason.
#
# The allowance is pinned to the CURRENT session id, so the negative cases below
# matter more than the positive one: a bare /tmp path, another session's scratchpad,
# and a lookalike directory must all still deny.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SID="11111111-2222-3333-4444-555555555555"
OTHER="99999999-8888-7777-6666-555555555555"
THIRD="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

verdict() { # file_path, session_id [, alias lines for that id] -> "allow" | "DENY"
  local st out
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$st/scope/.sid-alias-$2"
  out=$(FP="$1" PROJ="$st" python3 -c '
import json, os
print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": os.environ["FP"], "content": "x"},
                  "cwd": os.environ["PROJ"]}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" CLAUDE_CODE_SESSION_ID="$2" \
      bash "$REPO_DIR/hooks/path-guard.sh" 2>/dev/null)
  rm -rf "$st"
  if printf '%s' "$out" | grep -q 'permissionDecision'; then printf 'DENY'; else printf 'allow'; fi
}

echo "=== Harness Scratchpad Write Tests ==="

begin_test "the current session's scratchpad is writable via the Write tool"
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$SID/scratchpad/notes.md" "$SID")
[ "$V" = "allow" ] && pass || fail "scratchpad still denied ($V)"

begin_test "a nested file inside the scratchpad is writable too"
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$SID/scratchpad/sub/dir/out.json" "$SID")
[ "$V" = "allow" ] && pass || fail "nested scratchpad path denied ($V)"

begin_test "GAP CHECK: this is not a general /tmp allowance"
V=$(verdict "/private/tmp/claude-501/evil.sh" "$SID")
[ "$V" = "DENY" ] && pass || fail "bare temp path allowed — the carve-out is too wide ($V)"

begin_test "GAP CHECK: another session's scratchpad is still denied"
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$OTHER/scratchpad/notes.md" "$SID")
[ "$V" = "DENY" ] && pass || fail "cross-session scratchpad write allowed ($V)"

begin_test "GAP CHECK: a lookalike directory name is still denied"
# `scratchpad-evil` must not satisfy the marker; the separator is load-bearing.
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$SID/scratchpad-evil/x.sh" "$SID")
[ "$V" = "DENY" ] && pass || fail "lookalike dir allowed ($V)"

begin_test "GAP CHECK: the session id must be a whole path segment"
V=$(verdict "/private/tmp/claude-501/prefix-$SID/scratchpad/x.sh" "$SID")
[ "$V" = "DENY" ] && pass || fail "partial session-id segment allowed ($V)"

begin_test "GAP CHECK: with no session id, nothing is carved out"
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$SID/scratchpad/notes.md" "")
[ "$V" = "DENY" ] && pass || fail "empty session id still allowed the write ($V)"

begin_test "after a resume, the new id's scratchpad is writable when recorded as an alias"
# Tool calls carry the OLD id ($SID); the system prompt may name the NEW one ($OTHER).
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$OTHER/scratchpad/notes.md" "$SID" "$OTHER")
[ "$V" = "allow" ] && pass || fail "aliased scratchpad denied ($V)"

begin_test "GAP CHECK: an alias recorded for another session does not carry over"
V=$(verdict "/private/tmp/claude-501/-Users-x-proj/$OTHER/scratchpad/notes.md" "$THIRD" "$SID")
[ "$V" = "DENY" ] && pass || fail "unrelated alias allowed the write ($V)"

begin_test "GAP CHECK: a non-id line in the alias file widens nothing"
V=$(verdict "/private/tmp/claude-501/x/scratchpad/notes.md" "$SID" "x")
[ "$V" = "DENY" ] && pass || fail "junk alias line allowed the write ($V)"

begin_test "SessionStart on a resume records the new id under the transcript's id"
ST=$(mktemp -d); mkdir -p "$ST/scope" "$ST/home" "$ST/proj"
printf '{"session_id":"%s","transcript_path":"/x/projects/p/%s.jsonl","cwd":"%s","source":"resume"}' "$OTHER" "$SID" "$ST/proj" \
  | env HOME="$ST/home" SUPERCHARGER_STATE="$ST" CLAUDE_CODE_SESSION_ID="$OTHER" bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1
A=$(cat "$ST/scope/.sid-alias-$SID" 2>/dev/null)
[ "$A" = "$OTHER" ] && pass || fail "alias file: '$A'"

begin_test "GAP CHECK: a fresh session (transcript named after itself) records no alias"
printf '{"session_id":"%s","transcript_path":"/x/projects/p/%s.jsonl","cwd":"%s","source":"startup"}' "$THIRD" "$THIRD" "$ST/proj" \
  | env HOME="$ST/home" SUPERCHARGER_STATE="$ST" CLAUDE_CODE_SESSION_ID="$THIRD" bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1
[ ! -e "$ST/scope/.sid-alias-$THIRD" ] && pass || fail "alias written for a fresh session"
rm -rf "$ST"

begin_test "GAP CHECK: credential dirs are unaffected by the carve-out"
V=$(verdict "$HOME/.ssh/authorized_keys" "$SID")
[ "$V" = "DENY" ] && pass || fail "ssh write allowed ($V)"

report
