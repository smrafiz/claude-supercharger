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

# --- v4.0.26: an unreadable artifact is not a clean scan -----------------------
# `CONTENT=$(head -c ... || true)` then `[ -z "$CONTENT" ] && exit 0` gave the SAME
# verdict to "the file is empty" and "the file could not be read" — so an
# unreadable page published unscanned, from the one hook that gates irreversible
# egress. [[failure-modes-collapse-to-one-verdict]], the `|| PY_REASON=""` shape.
APG_TD=$(mktemp -d)
# native_path for the WRITER, not the reader. On Git Bash python3 is native
# Windows Python: it resolves the MSYS path /tmp/tmp.X against the current drive
# (C:\tmp\tmp.X), which does not exist, so every open() raised and NO fixture was
# written -- while MSYS bash reads the same /tmp path correctly. The guard is
# fine; only the fixture creation was on the wrong side of the boundary.
python3 -c "
import sys
key='sk-ant-'+'api03'+'-'+'D'*95
open(sys.argv[1]+'/secret.html','w').write('<html>'+key+'</html>')
open(sys.argv[1]+'/clean.html','w').write('<html>hello</html>')
open(sys.argv[1]+'/empty.html','w').write('')" "$(native_path "$APG_TD")"

begin_test "artifact: the fixtures this block asserts on actually exist"
# Setup that fails silently is worse here than anywhere else in this file: with no
# file on disk the guard exits 0 at its `[ -f ]`, so the empty-file and clean-page
# assertions BOTH pass for the wrong reason and only the deny baseline goes red.
# That is what Windows CI showed -- one failure hiding two hollow passes. Assert
# the precondition so a broken setup reads as a broken setup.
# [[failure-modes-collapse-to-one-verdict]] again: "nothing to scan" and "nothing
# was written" must not share an exit.
# Existence is not enough. A file that exists but is EMPTY sends the guard down
# its `[ -z "$CONTENT" ]` branch, where a non-empty stat check fails and it exits
# 0 silently -- so the deny assertion below reports "none" while this one still
# passes. That is the same collapse this block exists to test, reproduced in the
# test's own precondition. Assert the bytes, not the inode.
_APG_MISSING=""
for _f in secret.html clean.html; do
  [ -s "$APG_TD/$_f" ] || _APG_MISSING="$_APG_MISSING $_f(empty-or-absent)"
done
[ -f "$APG_TD/empty.html" ] || _APG_MISSING="$_APG_MISSING empty.html(absent)"
grep -q 'sk-ant-' "$APG_TD/secret.html" 2>/dev/null \
  || _APG_MISSING="$_APG_MISSING secret.html(no-key-in-content)"
[ -z "$_APG_MISSING" ] && pass || fail "fixture setup is wrong —$_APG_MISSING"
# Verdict by BASH PATTERN MATCH on the captured stdout, not by piping it to grep.
#
# Measured on Git Bash (run 33906311017): the hook writes 604 bytes of correct
# JSON to stdout and exits 2, and `grep -o` against that same stream matched
# NOTHING. rc, stderr and the bytes themselves all arrive; only the grep fails.
# So the guard is right and the harness was wrong — this was the one assertion in
# the file reading its verdict through an external grep, and the one that failed
# for three CI rounds while eleven siblings asserting rc stayed green.
#
# `case` is a bash builtin: no fork, no locale, no binary-detection heuristic, no
# MSYS text-mode translation between the hook and the assertion. It tests exactly
# the property the grep was meant to test.
apg() {
  APG_OUT=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Artifact","cwd":sys.argv[2],"session_id":"apg","tool_input":{"file_path":sys.argv[1],"title":"t"}}))' "$1" "$APG_TD" \
    | bash "$GUARD" 2>/dev/null)
  case "$APG_OUT" in
    *'"permissionDecision":"deny"'*) echo deny ;;
    *'"permissionDecision":"ask"'*)  echo ask ;;
    *)                               echo none ;;
  esac
}

begin_test "artifact: a readable page carrying a credential is still denied"
# On failure, report WHY rather than only the verdict. This assertion went red on
# Git Bash twice while every neighbouring assertion passed, and "none" alone does
# not distinguish an unwritten file from an unmatched pattern from an unread path.
# The diagnostics cost nothing on the passing path.
if [ "$(apg "$APG_TD/secret.html")" = deny ]; then
  pass
else
  _APG_SZ=$(wc -c < "$APG_TD/secret.html" 2>/dev/null | tr -d ' ')
  _APG_HEAD=$(head -c 30 "$APG_TD/secret.html" 2>/dev/null | tr -d '\0')
  _APG_RC=$(printf '{"tool_name":"Artifact","cwd":"%s","session_id":"apg","tool_input":{"file_path":"%s","title":"t"}}' \
    "$APG_TD" "$APG_TD/secret.html" | bash "$GUARD" >/dev/null 2>&1; echo $?)
  _APG_ERR=$(printf '{"tool_name":"Artifact","cwd":"%s","session_id":"apg","tool_input":{"file_path":"%s","title":"t"}}' \
    "$APG_TD" "$APG_TD/secret.html" | bash "$GUARD" 2>&1 >/dev/null | head -1)
  # Round 2. Round 1 proved the file is written, the content is right, the guard
  # DENIES (rc=2) and its stderr is correct -- so the hook works and only the
  # STDOUT JSON fails to arrive. Every other deny assertion in this file checks
  # rc via _art_rc; this block is the only one that greps stdout, and the only
  # one that fails. So measure stdout itself: how many bytes, and what they are.
  _APG_OUT=$(printf '{"tool_name":"Artifact","cwd":"%s","session_id":"apg","tool_input":{"file_path":"%s","title":"t"}}' \
    "$APG_TD" "$APG_TD/secret.html" | bash "$GUARD" 2>/dev/null | od -c | head -3 | tr '\n' '~')
  _APG_OUTN=$(printf '{"tool_name":"Artifact","cwd":"%s","session_id":"apg","tool_input":{"file_path":"%s","title":"t"}}' \
    "$APG_TD" "$APG_TD/secret.html" | bash "$GUARD" 2>/dev/null | wc -c | tr -d ' ')
  fail "baseline lost: $(apg "$APG_TD/secret.html") | bytes=${_APG_SZ:-?} head='${_APG_HEAD}' rc=$_APG_RC stderr='${_APG_ERR}' stdout_bytes=${_APG_OUTN} stdout=${_APG_OUT}"
fi

begin_test "artifact: a genuinely EMPTY file is still a no-op, not an ask"
[ "$(apg "$APG_TD/empty.html")" = none ] && pass || fail "fired on an empty file"

begin_test "artifact: a readable clean page is still silent"
[ "$(apg "$APG_TD/clean.html")" = none ] && pass || fail "fired on clean content"

# chmod is advisory on MSYS/NTFS, where the bit is derived from the file rather
# than stored — so gate on the PRECONDITION actually holding, never on a platform
# name. Same reasoning as v4.0.21's executable-bit test.
chmod 000 "$APG_TD/secret.html" 2>/dev/null || true
if [ -r "$APG_TD/secret.html" ]; then
  begin_test "artifact: unreadable-file case (skipped — filesystem ignores chmod)"
  pass
else
  begin_test "artifact: an unreadable page asks instead of publishing unscanned"
  [ "$(apg "$APG_TD/secret.html")" = ask ] && pass \
    || fail "unscanned publish allowed: $(apg "$APG_TD/secret.html")"
fi
chmod 644 "$APG_TD/secret.html" 2>/dev/null || true
rm -rf "$APG_TD"

report
