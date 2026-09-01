#!/usr/bin/env bash
# Suite for hooks/write-secret-guard.sh (v4.0.15)
#
# The secret patterns covered three channels — tool output, commits, prompts —
# and never the write itself. Measured against the installed harness before this
# hook existed: a private-key header, an AWS key and a GitHub token each written
# to an IN-PROJECT file were allowed by all 160 hooks. (An earlier run of that
# probe wrote to /tmp and was denied by path-guard for being outside the project,
# which says nothing about content — the numbers here come from the corrected one.)
#
# The false-positive half carries as much weight as the detection half. This runs
# on every Write and Edit, so a hook that prompts on ordinary source is one that
# gets switched off, and then none of it protects anything.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/write-secret-guard.sh"

# Literals assembled at runtime so this file never contains a whole secret — the
# same convention as test-secret-patterns.sh, and it keeps the repo greppable
# without tripping the guards on itself.
PK_HDR="-----BEGIN RSA PRIVATE"" KEY-----"
AWS_ID="AKIA""IOSFODNN7EXAMPLE"
GH_PAT="ghp_$(printf 'A%.0s' $(seq 1 36))"

# One state dir per call unless the caller passes one: the ack file lives under
# HOME, so a fresh HOME per call silently defeats the ask-once assertions. That
# is exactly how the first draft of these tests "failed".
_verdict() {  # $1 = payload JSON, $2 = optional HOME to share
  local home out
  home="${2:-$(mktemp -d)}"
  out=$(printf '%s' "$1" | (cd "$REPO_DIR" && HOME="$home" bash "$HOOK" 2>/dev/null))
  [ -z "${2:-}" ] && rm -rf "$home"
  case "$out" in *'"ask"'*) printf 'ask' ;; '') printf 'allow' ;; *) printf 'other' ;; esac
}
_write() {  # $1 = content, $2 = session, $3 = optional filename
  printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s/%s","content":%s}}' \
    "$2" "$REPO_DIR" "${3:-probe.ts}" "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

echo "=== write-secret-guard ==="

begin_test "write-secret: a private key header asks"
[ "$(_verdict "$(_write "$PK_HDR" s1)")" = ask ] && pass || fail "private key written without a prompt"

begin_test "write-secret: an AWS access key id asks"
[ "$(_verdict "$(_write "const k='$AWS_ID';" s2)")" = ask ] && pass || fail "AWS key written without a prompt"

begin_test "write-secret: a token arriving through Edit asks"
PL=$(printf '{"session_id":"s3","tool_name":"Edit","tool_input":{"file_path":"%s/probe.ts","old_string":"x","new_string":"%s"}}' "$REPO_DIR" "$GH_PAT")
[ "$(_verdict "$PL")" = ask ] && pass || fail "Edit channel is unguarded"

begin_test "write-secret: a token in ANY MultiEdit edit asks"
# Checking only the first edit would be a hole the size of the second one.
PL=$(printf '{"session_id":"s4","tool_name":"MultiEdit","tool_input":{"file_path":"%s/probe.ts","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"%s"}]}}' "$REPO_DIR" "$GH_PAT")
[ "$(_verdict "$PL")" = ask ] && pass || fail "only the first MultiEdit edit is scanned"

# --- it must stay silent on everything else ----------------------------------
begin_test "write-secret: ordinary source is silent"
[ "$(_verdict "$(_write "export const x = 1;" s5)")" = allow ] && pass || fail "prompted on ordinary code"

begin_test "write-secret: prose ABOUT secrets is silent"
[ "$(_verdict "$(_write "// never commit your api key to git" s6)")" = allow ] && pass || fail "prompted on a comment"

begin_test "write-secret: a base64 asset blob is silent"
B64=$(python3 -c '
import base64, random
random.seed(3)
print(base64.b64encode(bytes(random.getrandbits(8) for _ in range(3000))).decode())')
[ "$(_verdict "$(_write "$B64" s7)")" = allow ] && pass || fail "prompted on a base64 blob"

begin_test "write-secret: a checksum manifest is silent"
# The v4.0.14 false positive, asserted on this channel too — the pattern library
# is shared, so a regression there would surface here as well.
[ "$(_verdict "$(_write "8005a3491db7d92f36ac66369861589f9c47123d3a7c71e643fc2c06168cd45a  package.json" s8)")" = allow ] \
  && pass || fail "prompted on a sha256 manifest"

begin_test "write-secret: a secret-shaped PATH with clean content is silent"
# The gate greps the whole payload, which includes the file path. Without the
# second, precise check on the written text alone, this would prompt on a write
# that carries no secret at all.
[ "$(_verdict "$(_write "just notes" s9 "$AWS_ID-notes.md")")" = allow ] && pass || fail "prompted on a path-only match"

# --- UX and controls ----------------------------------------------------------
begin_test "write-secret: asks once per file per session"
H=$(mktemp -d)
A=$(_verdict "$(_write "$PK_HDR" s10)" "$H")
B=$(_verdict "$(_write "$PK_HDR" s10)" "$H")
[ "$A" = ask ] && [ "$B" = allow ] && pass || fail "expected ask then allow, got $A then $B"

begin_test "write-secret: a DIFFERENT file in the same session still asks"
C=$(_verdict "$(_write "$PK_HDR" s10 "other.ts")" "$H")
[ "$C" = ask ] && pass || fail "the ack leaked across files"
rm -rf "$H"

begin_test "write-secret: the kill switch is honoured"
OUT=$(printf '%s' "$(_write "$PK_HDR" s11)" \
  | (cd "$REPO_DIR" && HOME="$(mktemp -d)" SUPERCHARGER_WRITE_SECRET_GUARD=0 bash "$HOOK" 2>/dev/null))
[ -z "$OUT" ] && pass || fail "SUPERCHARGER_WRITE_SECRET_GUARD=0 did not silence it"

begin_test "write-secret: the prompt never echoes the secret VALUE"
# This hook must not become the leak it guards against: output-secrets-scanner
# exists to stop credentials reaching the transcript, and a prompt that quotes
# the match would put one there.
OUT=$(printf '%s' "$(_write "${PK_HDR}MIIEowIBAAKCAQEA" s12)" \
  | (cd "$REPO_DIR" && HOME="$(mktemp -d)" bash "$HOOK" 2>/dev/null))
case "$OUT" in
  *MIIEowIBAAKCAQEA*) fail "the written value was echoed into the prompt" ;;
  *'"ask"'*) pass ;;
  *) fail "expected an ask decision, got: ${OUT:0:70}" ;;
esac

begin_test "write-secret: the prompt is parseable permissionDecision JSON"
printf '%s' "$(_write "$PK_HDR" s13)" \
  | (cd "$REPO_DIR" && HOME="$(mktemp -d)" bash "$HOOK" 2>/dev/null) \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)["hookSpecificOutput"]
sys.exit(0 if d["permissionDecision"]=="ask" and d["permissionDecisionReason"] else 1)' \
  && pass || fail "output is not a valid ask decision"

begin_test "write-secret: patterns come from the shared library, not a copy"
# The reason this hook exists is that channels drifted while the patterns did
# not. A private list here would recreate the drift it was written to close.
grep -q 'lib-secret-patterns.sh' "$HOOK" && pass || fail "does not source the shared pattern library"
grep -qE "^\s*(SECRET_PATTERNS=\(|_WSG_RE='\()" "$HOOK" && fail "declares its own pattern list" || pass

report
