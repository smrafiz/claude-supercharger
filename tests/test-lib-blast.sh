#!/usr/bin/env bash
# lib-blast.sh push count. The count runs before the command, so in
# `git commit … && git push` the commit it makes was missing: the prompt said
# "pushes 0 commit(s)" for a command that pushed one.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=../hooks/lib-blast.sh
source "$REPO_DIR/hooks/lib-blast.sh"

echo "=== lib-blast push count ==="

T=$(mktemp -d)
git init -q --bare "$T/o"
git clone -q "$T/o" "$T/w" 2>/dev/null
cd "$T/w" || exit 1
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
git push -q origin HEAD 2>/dev/null
git branch -q --set-upstream-to="origin/$(git branch --show-current)" 2>/dev/null

begin_test "blast: commit && push counts the commit the command makes"
blast_summary 'git commit -m b && git push origin HEAD'
case "$BLAST" in "pushes 1 commit(s)"*"counting the one this command commits first"*) pass ;; *) fail "BLAST=$BLAST" ;; esac

begin_test "blast: a bare push counts only what is already ahead"
blast_summary 'git push origin HEAD'
case "$BLAST" in "pushes 0 commit(s) to origin/"*) case "$BLAST" in *counting*) fail "BLAST=$BLAST" ;; *) pass ;; esac ;; *) fail "BLAST=$BLAST" ;; esac

begin_test "blast: commit --amend && push adds nothing (it replaces HEAD)"
blast_summary 'git commit --amend --no-edit && git push -f origin HEAD'
case "$BLAST" in "pushes 0 commit(s)"*) pass ;; *) fail "BLAST=$BLAST" ;; esac

begin_test "blast: a commit after the push is not counted"
blast_summary 'git push origin HEAD && git commit -m c'
case "$BLAST" in "pushes 0 commit(s)"*) pass ;; *) fail "BLAST=$BLAST" ;; esac

cd / && rm -rf "$T"
report
