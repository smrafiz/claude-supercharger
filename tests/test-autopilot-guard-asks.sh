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

rm -rf "$H" "$ST"
report
