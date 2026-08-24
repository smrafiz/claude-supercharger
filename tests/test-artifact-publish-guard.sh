#!/usr/bin/env bash
# Artifact publish guard (v2.26.44)
#
# The Artifact tool renders a local file to a page hosted on claude.ai. That is a
# first-class egress primitive — content leaves the machine — and NOTHING guarded
# it. Found by diffing the tools present in a live session against our registered
# matchers: 15 tools had zero coverage, and this was the one with a real
# irreversible external effect.
#
# Why DENY and not warn, unlike output-secrets-scanner: that hook tells Claude not
# to REPEAT a value it already read locally. This one stops the value leaving. A
# published page can be cached, indexed, or shared onward even after deletion, so
# the failure is not recoverable by noticing it afterwards.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/artifact-publish-guard.sh"

echo "=== Artifact Publish Guard Tests ==="

# Assembled at runtime: a literal live-shaped key in this file would be caught by
# our own commit-secret-guard when the suite is committed.
AWS_ID="AKIA$(printf 'IOSFODNN7EXAMPLE')"
SLACK_TOK="xoxb-$(printf '2444')-$(printf '2403')-$(printf 'abcdefghijklmnopqrstuvwx')"

publish() { # file, [action] -> sets RC/OUT
  local f="$1" act="${2:-}" payload
  if [ -n "$act" ]; then
    payload=$(printf '{"tool_name":"Artifact","tool_input":{"action":"%s","file_path":"%s"},"cwd":"/tmp"}' "$act" "$f")
  else
    payload=$(printf '{"tool_name":"Artifact","tool_input":{"file_path":"%s"},"cwd":"/tmp"}' "$f")
  fi
  OUT=$(printf '%s' "$payload" | bash "$GUARD" 2>&1)
  RC=$?
}

mkpage() { # content -> echoes path
  local d; d=$(mktemp -d)
  printf '<h1>Report</h1>\n%s\n' "$1" > "$d/page.html"
  printf '%s' "$d/page.html"
}

# --- blocks ------------------------------------------------------------------
begin_test "blocks publishing a file containing an AWS access key"
F=$(mkpage "const key = '$AWS_ID';")
publish "$F"
rm -rf "$(dirname "$F")"
[ "$RC" -eq 2 ] && pass || fail "expected deny, got rc=$RC out=$OUT"

begin_test "blocks a Slack bot token"
F=$(mkpage "token: $SLACK_TOK")
publish "$F"
rm -rf "$(dirname "$F")"
[ "$RC" -eq 2 ] && pass || fail "expected deny, got rc=$RC"

begin_test "blocks a private key block"
F=$(mkpage "$(printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----')")
publish "$F"
rm -rf "$(dirname "$F")"
[ "$RC" -eq 2 ] && pass || fail "expected deny, got rc=$RC"

begin_test "the denial explains that publishing is irreversible"
F=$(mkpage "key=$AWS_ID")
publish "$F"
rm -rf "$(dirname "$F")"
printf '%s' "$OUT" | grep -qi 'not reversible\|cached' && pass || fail "reason does not explain the stakes: $OUT"

begin_test "the denial is valid JSON with a deny decision"
F=$(mkpage "key=$AWS_ID")
publish "$F"
rm -rf "$(dirname "$F")"
printf '%s' "$OUT" | grep -v '^\[Supercharger\]' | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['hookSpecificOutput']['permissionDecision'] == 'deny'
" 2>/dev/null && pass || fail "malformed hook output: $OUT"

# --- allows ------------------------------------------------------------------
begin_test "a clean page publishes silently"
F=$(mkpage "<p>Quarterly revenue rose 12%.</p>")
publish "$F"
rm -rf "$(dirname "$F")"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass || fail "clean page blocked: rc=$RC out=$OUT"

begin_test "action:list is never touched (it publishes nothing)"
F=$(mkpage "key=$AWS_ID")
publish "$F" list
rm -rf "$(dirname "$F")"
[ "$RC" -eq 0 ] && pass || fail "list action blocked: rc=$RC"

begin_test "a missing file is not an error"
publish "/nonexistent/nope.html"
[ "$RC" -eq 0 ] && pass || fail "missing file errored: rc=$RC"

begin_test "a payload with no file_path exits fast"
OUT=$(printf '{"tool_name":"Artifact","tool_input":{"action":"list"}}' | bash "$GUARD" 2>&1); RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass || fail "no-file payload: rc=$RC out=$OUT"

begin_test "prose that merely mentions credentials is not blocked"
F=$(mkpage "<p>Rotate the API key and store the token in the vault.</p>")
publish "$F"
rm -rf "$(dirname "$F")"
[ "$RC" -eq 0 ] && pass || fail "false positive on prose: rc=$RC out=$OUT"

# --- shared pattern source ---------------------------------------------------
begin_test "patterns come from lib-secret-patterns, not a local copy"
grep -q 'lib-secret-patterns' "$GUARD" && pass || fail "guard does not source the shared patterns"

begin_test "no SECRET_PATTERNS array is redefined in this guard"
grep -q '^SECRET_PATTERNS=(' "$GUARD" && fail "guard defines its own pattern list — it will drift" || pass

begin_test "a new shared pattern is honoured without touching this guard"
# Proves the sourcing is live rather than decorative.
# Assignment on its own line: test-repo-tree-isolation grows its repo-rooted set
# from `NAME=<rhs>`, and on a compound line the rhs swallows the following
# `cp … "$REPO_DIR/hooks"`, marking this temp path repo-rooted.
TD=$(mktemp -d)
cp -R "$REPO_DIR/hooks" "$TD/hooks"
printf 'SECRET_PATTERNS+=("ZZTOPSECRET[0-9]{4}")\n' >> "$TD/hooks/lib-secret-patterns.sh"
F=$(mkpage "value ZZTOPSECRET1234 here")
OUT=$(printf '{"tool_name":"Artifact","tool_input":{"file_path":"%s"},"cwd":"/tmp"}' "$F" \
  | bash "$TD/hooks/artifact-publish-guard.sh" 2>&1); RC=$?
rm -rf "$TD" "$(dirname "$F")"
[ "$RC" -eq 2 ] && pass || fail "shared pattern additions not picked up: rc=$RC"

# --- registration ------------------------------------------------------------
begin_test "registered on PreToolUse:Artifact (before the publish, not after)"
grep -q 'PreToolUse|Artifact|.*artifact-publish-guard.sh' "$REPO_DIR/lib/hooks.sh" && pass \
  || fail "not registered as PreToolUse|Artifact"

begin_test "generated hooks.json carries the registration"
grep -q 'artifact-publish-guard' "$REPO_DIR/hooks/hooks.json" && pass \
  || fail "run tools/gen-plugin-hooks.sh — lib/hooks.sh and hooks.json have drifted"

begin_test "hook is executable"
[ -x "$GUARD" ] && pass || fail "not executable (Write creates 0644)"

begin_test "the block is recorded in the ledger for /why"
ST=$(mktemp -d); mkdir -p "$ST/scope"
F=$(mkpage "key=$AWS_ID")
printf '{"tool_name":"Artifact","tool_input":{"file_path":"%s"},"cwd":"/tmp"}' "$F" \
  | SUPERCHARGER_STATE="$ST" bash "$GUARD" >/dev/null 2>&1 || true
grep -q 'credentials' "$ST/scope/.blocked-commands" 2>/dev/null && pass || fail "not written to the block ledger"
rm -rf "$ST" "$(dirname "$F")"

# --- reply / room_send: the same egress primitive as publish (v2.29.15) ---
# The guard fast-pathed on file_path only, so neither outbound-TEXT action ever
# reached a line of it: a credential in either returned 0 while the identical key
# in a published file returned 2. Found by sweeping the extracted CC tool
# descriptions for rules stated with no mechanism behind them — the same signal
# that produced workflow-guard and sendmessage-guard.
AWSSUF="IOSFODNN7EXAMPLE"

_art_rc() {  # $1 = action, $2 = payload value -> guard exit code
  ART_A="$1" ART_V="$2" python3 -c "
import json,os
a=os.environ['ART_A']; v=os.environ['ART_V']
ti={'action':a,'url':'https://claude.ai/code/artifact/x'}
ti.update({'thread_id':'t1','text':v} if a=='reply' else {'topic':'sync','data':{'k':v}})
print(json.dumps({'tool_name':'Artifact','tool_input':ti}))" \
    | bash "$GUARD" >/dev/null 2>&1
  echo $?
}

begin_test "artifact-reply: DENY a credential posted into a comment thread"
[ "$(_art_rc reply "token AKIA$AWSSUF")" = "2" ] && pass || fail "credential in reply text not blocked"

begin_test "artifact-room_send: DENY a credential broadcast to live viewers"
# room_send reaches everyone viewing the page right now, and the tool's own rule
# ("never send workspace or conversation content to the room") has no mechanism.
[ "$(_art_rc room_send "token AKIA$AWSSUF")" = "2" ] && pass || fail "credential in room_send data not blocked"

begin_test "artifact-reply: a clean reply is allowed"
[ "$(_art_rc reply 'just a status note')" = "0" ] && pass || fail "clean reply was blocked"

begin_test "artifact-room_send: a clean broadcast is allowed"
[ "$(_art_rc room_send 'build finished')" = "0" ] && pass || fail "clean room_send was blocked"

begin_test "artifact: the publish path is unchanged by the reply/room_send branch"
# The new branch returns before the file-reading code; publish must still deny.
PF=$(mktemp -d)/p.html; printf 'const K = "AKIA%s";\n' "$AWSSUF" > "$PF"
printf '{"tool_name":"Artifact","tool_input":{"file_path":"%s"},"cwd":"/tmp"}' "$PF" \
  | bash "$GUARD" >/dev/null 2>&1
RC=$?; rm -rf "$(dirname "$PF")"
[ "$RC" = "2" ] && pass || fail "publish regressed, rc=$RC"

begin_test "artifact: an outbound action with no text or data is a no-op"
RC=$(printf '{"tool_name":"Artifact","tool_input":{"action":"room_send","url":"u","topic":"t"}}' \
  | bash "$GUARD" >/dev/null 2>&1; echo $?)
[ "$RC" = "0" ] && pass || fail "bodyless room_send should pass, rc=$RC"

report
