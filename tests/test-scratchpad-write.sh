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

verdict() { # file_path, session_id -> "allow" | "DENY"
  local st out
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
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

begin_test "GAP CHECK: credential dirs are unaffected by the carve-out"
V=$(verdict "$HOME/.ssh/authorized_keys" "$SID")
[ "$V" = "DENY" ] && pass || fail "ssh write allowed ($V)"

report
