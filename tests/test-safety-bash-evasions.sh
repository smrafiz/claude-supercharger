#!/usr/bin/env bash
# Suite for safety.sh bash-channel evasions closed in v2.22.2.
# Payloads live inside this file (not on a command line) so the live installed
# guard doesn't block the test runner itself.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/safety.sh"

# verdict <command> → BLOCK|ALLOW
verdict() {
  local j; j=$(printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  bash "$H" <<<"$j" >/dev/null 2>&1 && echo ALLOW || echo BLOCK
}

# ---- Finding 1: & background operator + bash -c ----
begin_test "safety: 'x & bash -c <destructive>' is blocked (& anchor)"
[ "$(verdict "true & bash -c 'rm -rf /tmp/zzz'")" = BLOCK ] && pass || fail "& bash -c evaded"
begin_test "safety: 'x & eval ...' is blocked"
[ "$(verdict "sleep 0 & eval \"\$P\"")" = BLOCK ] && pass || fail "& eval evaded"

# ---- Finding 6: SQL /**/ comment separator ----
begin_test "safety: DROP/**/TABLE is blocked"
[ "$(verdict "psql -c \"DROP/**/TABLE users\"")" = BLOCK ] && pass || fail "DROP/**/TABLE evaded"
begin_test "safety: TRUNCATE/**/ is blocked"
[ "$(verdict "mysql -e \"TRUNCATE/**/accounts\"")" = BLOCK ] && pass || fail "TRUNCATE/**/ evaded"

# ---- Finding 3: shell-profile quote + copy verbs ----
begin_test "safety: >> \"\$HOME/.bashrc\" (quoted) is blocked"
[ "$(verdict "echo evil >> \"\$HOME/.bashrc\"")" = BLOCK ] && pass || fail "quoted profile redirect evaded"
begin_test "safety: cp into ~/.bashrc is blocked"
[ "$(verdict "cp /tmp/x ~/.bashrc")" = BLOCK ] && pass || fail "cp profile write evaded"
begin_test "safety: rsync into ~/.zshrc is blocked"
[ "$(verdict "rsync /tmp/x ~/.zshrc")" = BLOCK ] && pass || fail "rsync profile write evaded"

# ---- Finding 5: selfmod rsync into .disabled-security-categories ----
begin_test "safety: rsync into .disabled-security-categories is blocked"
[ "$(verdict "rsync /tmp/x ~/.claude/supercharger/scope/.disabled-security-categories")" = BLOCK ] && pass || fail "rsync selfmod evaded"

# ---- regressions: existing blocks still fire ----
begin_test "safety: plain 'rm -rf /' still blocked"
[ "$(verdict "rm -rf /")" = BLOCK ] && pass || fail "rm -rf / regressed"
begin_test "safety: 'DROP TABLE users' (plain) still blocked"
[ "$(verdict "psql -c \"DROP TABLE users\"")" = BLOCK ] && pass || fail "plain DROP TABLE regressed"
begin_test "safety: 'echo x >> ~/.bashrc' (plain) still blocked"
[ "$(verdict "echo x >> ~/.bashrc")" = BLOCK ] && pass || fail "plain profile redirect regressed"

# ---- regressions: benign commands still allowed ----
begin_test "safety: 'git status' still allowed"
[ "$(verdict "git status")" = ALLOW ] && pass || fail "git status over-blocked"
begin_test "safety: 'ls -la && echo done' still allowed"
[ "$(verdict "ls -la && echo done")" = ALLOW ] && pass || fail "benign compound over-blocked"
begin_test "safety: 'cp a.txt b.txt' (normal copy) still allowed"
[ "$(verdict "cp a.txt b.txt")" = ALLOW ] && pass || fail "normal cp over-blocked"

report
