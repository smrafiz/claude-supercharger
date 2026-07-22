#!/usr/bin/env bash
# Suite for human-approval-gate matcher hardening (v2.22.4).
# - migration category: prisma/drizzle (default-enabled but had no matcher → never blocked)
# - de-anchored git/infra/publish/docker/disk matchers (a leading sudo/env/cd&& dodged ^)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/human-approval-gate.sh"

jcmd() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
# verdict <command> → BLOCK (exit 2 / asks) | PASS (exit 0)
verdict() {
  local st; st=$(mktemp -d); mkdir -p "$st/scope"
  local j; j=$(printf '{"tool_name":"Bash","cwd":"/tmp","session_id":"hg","tool_input":{"command":%s}}' "$(jcmd "$1")")
  SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_STATE="$st" bash "$H" <<<"$j" >/dev/null 2>&1
  local rc=$?; rm -rf "$st"
  [ "$rc" -eq 0 ] && echo PASS || echo BLOCK
}

# ---- BYPASS-1: flagship default-gated commands now actually blocked ----
begin_test "human-approval: 'prisma migrate reset' is blocked"
[ "$(verdict "prisma migrate reset --force")" = BLOCK ] && pass || fail "prisma migrate reset not blocked"
begin_test "human-approval: 'drizzle-kit push --force' is blocked"
[ "$(verdict "drizzle-kit push --force")" = BLOCK ] && pass || fail "drizzle-kit push --force not blocked"

# ---- BYPASS-2: prefix no longer dodges the anchored matchers ----
begin_test "human-approval: 'sudo terraform destroy' is blocked"
[ "$(verdict "sudo terraform destroy")" = BLOCK ] && pass || fail "sudo terraform destroy evaded"
begin_test "human-approval: 'cd /x && kubectl delete namespace prod' is blocked"
[ "$(verdict "cd /x && kubectl delete namespace prod")" = BLOCK ] && pass || fail "cd&& kubectl delete evaded"
begin_test "human-approval: 'FOO=1 npm publish' is blocked"
[ "$(verdict "FOO=1 npm publish")" = BLOCK ] && pass || fail "env-prefix npm publish evaded"
begin_test "human-approval: 'true && docker system prune -af' is blocked"
[ "$(verdict "true && docker system prune -af")" = BLOCK ] && pass || fail "compound docker prune evaded"
begin_test "human-approval: 'x=1 git reset --hard' is blocked"
[ "$(verdict "x=1 git reset --hard")" = BLOCK ] && pass || fail "env-prefix git reset evaded"

# ---- regressions: plain forms still blocked ----
begin_test "human-approval: plain 'terraform destroy' still blocked"
[ "$(verdict "terraform destroy")" = BLOCK ] && pass || fail "plain terraform destroy regressed"

# ---- regressions: benign commands not blocked ----
begin_test "human-approval: 'git status' not blocked"
[ "$(verdict "git status")" = PASS ] && pass || fail "git status over-blocked"
begin_test "human-approval: 'ls -la' not blocked"
[ "$(verdict "ls -la")" = PASS ] && pass || fail "ls over-blocked"
begin_test "human-approval: 'npm run build' not blocked"
[ "$(verdict "npm run build")" = PASS ] && pass || fail "npm run build over-blocked"

report
