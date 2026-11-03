#!/usr/bin/env bash
# 2026-10-28 — a guard's ASK must not be auto-approved by an open autopilot window.
# Before this, smart-approve declined only a hand-kept list (sc-toggle, hook-toggle,
# trust-mcp, critical infra, lockfiles, mode changes), so every other guard confirm
# (a force push to a feature branch, LD_PRELOAD, a pushed amend) reached nobody.
# Flow under test: the guard runs (PreToolUse), then the permission prompt it raised
# goes to smart-approve (PermissionRequest) with the same tool input.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== autopilot never approves a guard's ask ==="

H=$(mktemp -d); mkdir -p "$H/.claude"
ST=$(mktemp -d); mkdir -p "$ST/scope"
echo $(( $(date +%s) + 3600 )) > "$ST/scope/.autopilot-until"

payload() {  # $1 = command, $2 = session
  printf '{"session_id":"%s","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$2" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"
}
guard() {  # $1 = hook, $2 = payload -> ask | deny | allow
  local out rc
  out=$(printf '%s' "$2" | HOME="$H" SUPERCHARGER_STATE="$ST" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/$1" 2>/dev/null); rc=$?
  case "$rc:$out" in 2:*|*'"deny"'*) echo deny ;; *'"ask"'*) echo ask ;; *) echo allow ;; esac
}
verdict() {  # 0 = auto-approved, 1 = declined
  HOME="$H" SUPERCHARGER_STATE="$ST" bash -c '
    . "$1/hooks/lib-smart-approve.sh"
    smart_approve_verdict "$2" && echo approved || echo declined
  ' _ "$REPO_DIR" "$1"
}

FP=$(payload "git push --force origin feat/x" s1)
LP=$(payload "LD_PRELOAD=/tmp/x.so ls" s1)
OK=$(payload "ls -la" s1)

begin_test "control: an open autopilot window approves an ordinary call"
[ "$(verdict "$OK")" = approved ] && pass || fail "autopilot did not approve ls; every check below is vacuous"

begin_test "control: the force push to a feature branch is an ASK"
[ "$(guard git-safety.sh "$FP")" = ask ] && pass || fail "git-safety did not ask"

begin_test "the asked force push is not auto-approved"
[ "$(verdict "$FP")" = declined ] && pass || fail "autopilot approved a call git-safety asked about"

begin_test "LD_PRELOAD: guard asks, autopilot declines"
g=$(guard safety.sh "$LP"); v=$(verdict "$LP")
[ "$g" = ask ] && [ "$v" = declined ] && pass || fail "guard=$g autopilot=$v"

begin_test "the same command in ANOTHER session is not affected"
[ "$(verdict "$(payload "git push --force origin feat/x" s2)")" = approved ] && pass || fail "key leaked across sessions"

begin_test "an ordinary call is still approved after asks were recorded"
[ "$(verdict "$OK")" = approved ] && pass || fail "recording an ask broke autopilot for unrelated calls"

# 4.4.3 spend guard: paying is never auto-approved, on either channel.
PAY=$(payload 'curl -H "X-PAYMENT: eyJ4" https://api.example.com/data' s1)
begin_test "x402 payment header: safety asks, autopilot declines"
g=$(guard safety.sh "$PAY"); v=$(verdict "$PAY")
[ "$g" = ask ] && [ "$v" = declined ] && pass || fail "guard=$g autopilot=$v"

MPAY='{"session_id":"s1","cwd":"/tmp","tool_name":"mcp__wallet__send_usdc","tool_input":{"to":"0xabc","amount":"5"}}'
begin_test "MCP payment tool: mcp-spend-guard asks, autopilot declines"
g=$(guard mcp-spend-guard.sh "$MPAY"); v=$(verdict "$MPAY")
[ "$g" = ask ] && [ "$v" = declined ] && pass || fail "guard=$g autopilot=$v"

# 2026-11-03: `/sc-autopilot <d> full` approves guard asks, except money, guards off
# and autopilot itself (asks a guard marks SC_ASK_KEEP).
CI='{"session_id":"s1","cwd":"/tmp/p","tool_name":"Write","tool_input":{"file_path":"/tmp/p/.github/workflows/ci.yml","content":"x"}}'
OFF=$(payload "bash ~/.claude/supercharger/tools/sc-toggle.sh off" s1)
REN=$(payload "bash ~/.claude/supercharger/tools/autopilot.sh 8h full" s1)
begin_test "control: without full a CI workflow write is declined"
[ "$(verdict "$CI")" = declined ] && pass || fail "plain autopilot approved a critical-infra write"
g_off=$(guard harness-tamper-guard.sh "$OFF"); g_ren=$(guard harness-tamper-guard.sh "$REN")

echo $(( $(date +%s) + 3600 )) > "$ST/scope/.autopilot-full"
begin_test "full approves the asked force push, LD_PRELOAD and a CI workflow write"
a=$(verdict "$FP"); b=$(verdict "$LP"); c=$(verdict "$CI")
[ "$a$b$c" = approvedapprovedapproved ] && pass || fail "push=$a preload=$b ci=$c"
begin_test "full still declines both payment asks"
a=$(verdict "$PAY"); b=$(verdict "$MPAY")
[ "$a$b" = declineddeclined ] && pass || fail "x402=$a mcp=$b"
begin_test "full still declines /sc off and autopilot renewing itself"
a=$(verdict "$OFF"); b=$(verdict "$REN")
[ "$g_off$g_ren" = askask ] && [ "$a$b" = declineddeclined ] && pass || fail "guard off=$g_off renew=$g_ren; autopilot off=$a renew=$b"
begin_test "an expired full window approves nothing extra"
echo $(( $(date +%s) - 1 )) > "$ST/scope/.autopilot-full"
[ "$(verdict "$FP")" = declined ] && pass || fail "expired full still approved the force push"

rm -rf "$H" "$ST"
report
