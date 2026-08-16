#!/usr/bin/env bash
# A heredoc body is data; a heredoc body fed to an interpreter is code.
#
# The guards match the raw command text, and that text includes heredoc bodies.
# Writing a test fixture containing the strings "DROP TABLE users" and
# "git reset --hard HEAD~1" was blocked FOUR times in one session — twice by
# safety.sh and twice by git-safety.sh — for lines destined for a file that no
# shell would ever run. Those four entries are in this machine's own block
# ledger. A gate that fires on inert data is the kind people switch off, and a
# disabled gate protects nothing.
#
# The exception carries the safety argument, so it is tested at least as hard as
# the fix: a body handed to something that EXECUTES it is still code. Shells,
# language interpreters and database clients keep their bodies, so stripping can
# never hide a payload — it only drops text headed for a file, a pager or a diff.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# shellcheck source=hooks/cmd-normalize.sh
. "$REPO_DIR/hooks/cmd-normalize.sh"

echo "=== Heredoc data vs code Tests ==="

HD=$(mktemp -d)

# Built with printf so this file never contains a runnable destructive line.
DQ="'"
mk_heredoc() {  # $1=opener  $2=body-line  $3=delimiter
  printf '%s <<%s%s%s\n%s\n%s\n' "$1" "$DQ" "$3" "$DQ" "$2" "$3"
}

# --- data bodies are stripped ------------------------------------------------
begin_test "a body written to a file is not treated as a command"
OUT=$(strip_heredoc_bodies "$(mk_heredoc 'cat > corpus.txt' 'DROP TABLE users' 'CORPUS')")
printf '%s' "$OUT" | grep -q 'DROP TABLE' && fail "data body survived: $OUT" || pass

begin_test "the owner is the command nearest the operator, not the first on the line"
OUT=$(strip_heredoc_bodies "$(mk_heredoc 'cd /tmp; cat > c.txt' 'git reset --hard HEAD~1' 'EOF')")
printf '%s' "$OUT" | grep -q 'reset --hard' && fail "data body survived: $OUT" || pass

begin_test "the command itself is preserved, only the body goes"
OUT=$(strip_heredoc_bodies "$(mk_heredoc 'cat > f' 'DROP TABLE t' 'EOF')")
printf '%s' "$OUT" | grep -q 'cat > f' && pass || fail "the command line was lost: $OUT"

# --- executed bodies are kept ------------------------------------------------
begin_test "a body handed to a shell is still code"
OUT=$(strip_heredoc_bodies "$(mk_heredoc 'bash' 'git reset --hard HEAD~1' 'EOF')")
printf '%s' "$OUT" | grep -q 'reset --hard' && pass || fail "a shell's body was stripped — the guard would go blind"

begin_test "a body handed to a database client is still code"
OUT=$(strip_heredoc_bodies "$(mk_heredoc 'psql' 'DROP TABLE users;' 'EOF')")
printf '%s' "$OUT" | grep -q 'DROP TABLE' && pass || fail "psql's body was stripped — SQL DDL would go unseen"

begin_test "a body PIPED into a shell is still code, though its owner is not one"
OUT=$(strip_heredoc_bodies "$(printf 'cat <<%sEOF%s | sh\ngit reset --hard\nEOF\n' "$DQ" "$DQ")")
printf '%s' "$OUT" | grep -q 'reset --hard' && pass || fail "piping the body to sh evaded the executor check"

begin_test "a herestring is left alone (it has no body)"
OUT=$(strip_heredoc_bodies "grep -q x <<< 'git reset --hard'")
printf '%s' "$OUT" | grep -q 'reset --hard' && pass || fail "<<< was treated as a heredoc"

begin_test "a command with no heredoc is returned unchanged"
IN="git reset --hard HEAD~1 && echo done"
[ "$(strip_heredoc_bodies "$IN")" = "$IN" ] && pass || fail "an ordinary command was rewritten"

# --- end to end: the guards themselves ---------------------------------------
# The unit tests above check the helper; these check the thing users hit.
guard_rc() {  # $1=command-file $2=hook -> rc
  python3 -c "
import json, os, sys
print(json.dumps({'tool_name': 'Bash',
                  'tool_input': {'command': open(sys.argv[1]).read()},
                  'cwd': os.environ['PWD']}))" "$1" > "$HD/pay.json" 2>/dev/null
  bash "$REPO_DIR/hooks/$2.sh" < "$HD/pay.json" >/dev/null 2>&1
  printf '%s' "$?"
}

# The data fixture carries BOTH a SQL string and a git string, because the two
# guards read different patterns: a body containing only SQL would leave the
# git-safety assertion below passing whether the fix is present or not. That is
# how the first draft of this file was written, and it is the failure mode this
# repo keeps finding — a test that is green because it never exercised anything.
{ printf 'cat > corpus.txt <<%sCORPUS%s\n' "$DQ" "$DQ"
  printf 'DROP TABLE users\n'
  printf 'git reset --hard HEAD~1\n'
  printf 'CORPUS\n'; } > "$HD/data.txt"
mk_heredoc 'bash' 'git reset --hard HEAD~1' 'EOF' > "$HD/code.txt"

begin_test "safety.sh allows a fixture whose body is data"
[ "$(guard_rc "$HD/data.txt" safety)" = "0" ] && pass || fail "still blocked — the four ledger entries would recur"

begin_test "git-safety.sh allows a fixture whose body is data"
[ "$(guard_rc "$HD/data.txt" git-safety)" = "0" ] && pass || fail "still blocked — the four ledger entries would recur"

begin_test "git-safety.sh still blocks a destructive body fed to a shell"
[ "$(guard_rc "$HD/code.txt" git-safety)" = "2" ] && pass || fail "the guard went blind on an executed heredoc"

rm -rf "$HD"

report
