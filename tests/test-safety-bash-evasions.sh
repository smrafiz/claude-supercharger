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

# ---- v2.29.31: the tee rule caught the MILDER form only --------------------
# v2.6.77 closed a reported `tee -a ~/.bashrc` bypass by REQUIRING an append flag.
# Plain `tee ~/.zshrc` therefore sailed through -- and that is the worse form,
# because without -a tee TRUNCATES the profile. Measured across all five profile
# targets before the fix: every one allowed the truncating form and blocked the
# appending one. Same class as v2.25.2 -- a fix applied to the reported branch of a
# regex, leaving its sibling open.
for _pf in .bashrc .zshrc .profile .bash_profile .zprofile; do
  begin_test "safety: truncating 'tee ~/$_pf' is blocked (not just tee -a)"
  [ "$(verdict "cat payload | tee ~/$_pf")" = BLOCK ] && pass || fail "plain tee to $_pf evaded"
  begin_test "safety: appending 'tee -a ~/$_pf' stays blocked"
  [ "$(verdict "cat payload | tee -a ~/$_pf")" = BLOCK ] && pass || fail "tee -a to $_pf regressed"
done

# Flags are consumed generically, so a combined or unrelated flag cannot slip past.
begin_test "safety: 'tee -ai' to a profile is blocked"
[ "$(verdict "cat x | tee -ai ~/.bashrc")" = BLOCK ] && pass || fail "combined flags evaded"
begin_test "safety: 'tee -p' to a profile is blocked"
[ "$(verdict "cat x | tee -p ~/.zshrc")" = BLOCK ] && pass || fail "unrelated flag evaded"

# Precision: tee is ordinary shell. Blocking it wholesale would be a nag.
begin_test "safety: 'tee' to a non-profile file is allowed"
[ "$(verdict "make 2>&1 | tee build.log")" = ALLOW ] && pass || fail "over-blocked a build log"
begin_test "safety: a profile NAME in prose is not a profile write"
[ "$(verdict "cat notes.md | grep bashrc")" = ALLOW ] && pass || fail "over-blocked prose"

# ---- v2.29.31: process substitution whose body is a shell -------------------
# Bash EXECUTES the substituted command, so `tee >(sh) < payload` has the same
# capability as piping into a shell, with no literal pipe-into-shell for the
# existing rule to match. From ggwhite/4x's allowlist, which treats `<(` and `>(`
# as execution markers alongside `$(` and backticks.
begin_test "safety: process substitution into a shell is blocked"
[ "$(verdict "tee >(sh) < payload.txt")" = BLOCK ] && pass || fail "process substitution into a shell evaded"
begin_test "safety: process substitution into bash -c is blocked"
[ "$(verdict "cat <(bash -c 'id')")" = BLOCK ] && pass || fail "bash -c substitution evaded"

# Precision: this must NOT become a blanket ban on process substitution, which is
# ordinary shell. Note `shasum` starts with the same two letters as `sh`.
begin_test "safety: 'diff <(sort a) <(sort b)' is allowed"
[ "$(verdict "diff <(sort a.txt) <(sort b.txt)")" = ALLOW ] && pass || fail "over-blocked ordinary process substitution"
begin_test "safety: 'diff <(shasum a) <(shasum b)' is allowed"
[ "$(verdict "diff <(shasum a) <(shasum b)")" = ALLOW ] && pass || fail "the sh- prefix over-matched"
begin_test "safety: 'wc -l < <(grep X log)' is allowed"
[ "$(verdict "wc -l < <(grep ERROR log.txt)")" = ALLOW ] && pass || fail "over-blocked a read-only substitution"

# --- v2.29.31: deleting .git destroys every commit, branch, stash and reflog ---
# The convoluted spelling was already blocked (`find . -name .git -exec rm -rf {} +`)
# while the obvious one was not. Same asymmetry as the tee rule above; surfaced by
# kenryu42/cc-safety-net's rm.git-metadata / find.delete-git-metadata pair.
# This is the command that makes every other git guard moot -- reset --hard and
# branch -D are survivable BECAUSE .git still exists.
begin_test "safety: '${RM} -rf .git' is blocked"
[ "$(verdict "rm -rf .git")" = BLOCK ] && pass || fail "rm -rf .git evaded"
begin_test "safety: '${RM} -rf ./.git' is blocked"
[ "$(verdict "rm -rf ./.git")" = BLOCK ] && pass || fail "./.git form evaded"
begin_test "safety: '${RM} -rf <abs>/.git' is blocked"
[ "$(verdict "rm -rf /srv/repo/.git")" = BLOCK ] && pass || fail "absolute form evaded"
begin_test "safety: '${RM} -r --force .git' is blocked (long flag)"
[ "$(verdict "rm -r --force .git")" = BLOCK ] && pass || fail "long flag form evaded"
begin_test "safety: '${RM} -rf .git/objects' is blocked"
[ "$(verdict "rm -rf .git/objects")" = BLOCK ] && pass || fail "internals form evaded"

# Precision: several ordinary dotfiles START with .git and are routine to delete.
begin_test "safety: '${RM} -rf .gitignore' is allowed"
[ "$(verdict "rm -rf .gitignore")" = ALLOW ] && pass || fail "over-blocked .gitignore"
begin_test "safety: '${RM} -f .gitattributes' is allowed"
[ "$(verdict "rm -f .gitattributes")" = ALLOW ] && pass || fail "over-blocked .gitattributes"
begin_test "safety: '${RM} .gitmodules' is allowed"
[ "$(verdict "rm .gitmodules")" = ALLOW ] && pass || fail "over-blocked .gitmodules"
begin_test "safety: '${RM} -rf node_modules' is allowed"
[ "$(verdict "rm -rf node_modules")" = ALLOW ] && pass || fail "over-blocked an ordinary dir"

report
