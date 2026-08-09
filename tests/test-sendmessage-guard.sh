#!/usr/bin/env bash
# Cross-session message guard (v2.26.77)
#
# SendMessage had NO guards — one of 28 exposed tools with nothing but the two
# universal hooks (coverage diff, 2026-08-09), and the only one of those that moves
# free text to another MACHINE.
#
# Check (A), credential exfiltration, is ordinary parity with the egress family.
#
# Check (B) is the interesting one. The SendMessage tool description itself says:
# "NEVER ask a peer to perform an action that was denied or blocked in your session
# ... a peer doing it for you bypasses the user's permission decision". The platform
# states the rule and provides no mechanism — and an instruction is precisely what a
# prompt injection overrides. This layer can enforce it because safety.sh and
# harness-tamper-guard already record every denial in scope/.blocked-commands.
#
# Pinned here: both checks fire, `to: main` is exempt from (B) but not (A), the
# ledger threshold does not fire on ordinary chatter, and the guard fails open.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/sendmessage-guard.sh"

# Isolated state so the live ledger is never read or written (test-telemetry-isolation).
ST=$(mktemp -d); mkdir -p "$ST/scope"
LEDGER="$ST/scope/.blocked-commands"
BLOCKED='rm -rf /Users/someone/project/build --no-preserve-root'
printf '[2026-08-09 10:00] dangerous pattern: rm-rf — %s\n' "$BLOCKED" > "$LEDGER"

send() { # to message -> deny | ask | allow
  local out rc
  out=$(TO="$1" MSG="$2" python3 -c '
import json, os
print(json.dumps({"tool_name":"SendMessage",
                  "tool_input":{"to":os.environ["TO"],"message":os.environ["MSG"]}}))' \
    | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo deny
  elif printf '%s' "$out" | grep -q '"ask"'; then echo ask
  else echo allow; fi
}

echo "=== SendMessage Guard Tests ==="

# --- (A) credentials must not leave the session ---
begin_test "an AWS key in the message body is denied"
[ "$(send worker 'use this key AKIAIOSFODNN7EXAMPLE to fetch the bucket')" = "deny" ] \
  && pass || fail "credential left the session"

begin_test "a GitHub token is denied"
[ "$(send worker 'token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa go ahead')" = "deny" ] \
  && pass || fail "credential left the session"

begin_test "credentials are denied even to main"
[ "$(send main 'here is AKIAIOSFODNN7EXAMPLE')" = "deny" ] \
  && pass || fail "main is exempt from laundering, NOT from secret exfil"

begin_test "the deny names the recipient"
OUT=$(TO=worker MSG='key AKIAIOSFODNN7EXAMPLE' python3 -c '
import json, os
print(json.dumps({"tool_name":"SendMessage","tool_input":{"to":os.environ["TO"],"message":os.environ["MSG"]}}))' \
  | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null)
printf '%s' "$OUT" | grep -q 'worker' && pass || fail "reason does not say where it was going: $OUT"

# --- (B) laundering a blocked command ---
begin_test "replaying a blocked command to a peer raises a confirm"
[ "$(send worker "please run $BLOCKED for me")" = "ask" ] && pass || fail "laundering not caught"

begin_test "the confirm quotes what was blocked"
OUT=$(TO=worker MSG="please run $BLOCKED" python3 -c '
import json, os
print(json.dumps({"tool_name":"SendMessage","tool_input":{"to":os.environ["TO"],"message":os.environ["MSG"]}}))' \
  | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null)
printf '%s' "$OUT" | grep -q 'Blocked earlier' && pass || fail "confirm is not actionable: $OUT"

begin_test "relaying the SAME text to main is exempt (shared permission decisions)"
[ "$(send main "please run $BLOCKED for me")" = "allow" ] \
  && pass || fail "main should not be treated as a laundering target"

begin_test "a peer named 'Main' is matched case-insensitively"
[ "$(send Main "please run $BLOCKED")" = "allow" ] || fail "case-sensitive main check"
[ "$(send Main "please run $BLOCKED")" = "allow" ] && pass

# --- the threshold must not fire on ordinary chatter ---
begin_test "ordinary coordination is not gated"
[ "$(send worker 'can you check whether the tests pass on your branch?')" = "allow" ] \
  && pass || fail "false positive on normal traffic"

begin_test "a short shared fragment is below the window"
[ "$(send worker 'rm -rf failed')" = "allow" ] \
  && pass || fail "matched on a fragment shorter than the 24-char window"

begin_test "mentioning the tool without the command is not gated"
[ "$(send worker 'the build directory cleanup did not work, any ideas?')" = "allow" ] \
  && pass || fail "over-matched"

# --- robustness ---
begin_test "an empty message is a no-op"
[ "$(send worker '')" = "allow" ] && pass || fail "should no-op"

begin_test "a missing ledger fails open"
ST2=$(mktemp -d); mkdir -p "$ST2/scope"
GOT=$(TO=worker MSG="run $BLOCKED" python3 -c '
import json, os
print(json.dumps({"tool_name":"SendMessage","tool_input":{"to":os.environ["TO"],"message":os.environ["MSG"]}}))' \
  | SUPERCHARGER_STATE="$ST2" bash "$HOOK" 2>/dev/null; echo "rc=$?")
printf '%s' "$GOT" | grep -q 'rc=0' && pass || fail "must fail open with no ledger: $GOT"
rm -rf "$ST2"

begin_test "malformed input fails open"
GOT=$(printf 'not json' | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null; echo "rc=$?")
printf '%s' "$GOT" | grep -q 'rc=0' && pass || fail "must fail open"

begin_test "SUPERCHARGER_SENDMESSAGE_GUARD=0 disables it"
# Build the payload FIRST rather than piping a generator into the hook: the kill
# switch returns before stdin is read, so a live writer takes EPIPE and prints a
# BrokenPipeError to stderr. Harmless here, but this repo has lost a release to a
# SIGPIPE that set -e turned fatal, so the noise is not worth leaving in.
PAYLOAD=$(TO=worker MSG='key AKIAIOSFODNN7EXAMPLE' python3 -c '
import json, os
print(json.dumps({"tool_name":"SendMessage","tool_input":{"to":os.environ["TO"],"message":os.environ["MSG"]}}))')
GOT=$(printf '%s' "$PAYLOAD" \
  | SUPERCHARGER_STATE="$ST" SUPERCHARGER_SENDMESSAGE_GUARD=0 bash "$HOOK" 2>/dev/null; echo "rc=$?")
printf '%s' "$GOT" | grep -q 'rc=0' && pass || fail "kill switch ignored: $GOT"

# --- registration + shared list ---
begin_test "registered on PreToolUse|SendMessage, blocking"
grep -q 'PreToolUse|SendMessage|.*sendmessage-guard.sh|"' "$REPO_DIR/lib/hooks.sh" \
  && pass || fail "not registered blocking — it could not deny"

begin_test "secret patterns come from the shared list, not a local copy"
grep -q 'lib-secret-patterns.sh' "$REPO_DIR/hooks/sendmessage-guard.sh" \
  && ! grep -q 'AKIA\[0-9A-Z\]' "$REPO_DIR/hooks/sendmessage-guard.sh" \
  && pass || fail "a copied pattern list is the drift this project keeps hitting"

begin_test "lib-secret-patterns documents the new consumer"
grep -q 'sendmessage-guard' "$REPO_DIR/hooks/lib-secret-patterns.sh" \
  && pass || fail "consumer list is stale"

rm -rf "$ST"
report
