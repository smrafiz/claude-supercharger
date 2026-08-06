#!/usr/bin/env bash
# Command substitution inside a double-quoted `-c "` block (v2.26.69)
#
# A `python3 -c "` … `"` block is a DOUBLE-QUOTED bash string, so bash expands
# backticks and $(...) inside it before the interpreter ever runs. Anything written
# there as illustration — an example path in a comment — gets executed.
#
# lib/hooks.sh carried a Windows example path in backticks inside such a comment, so
# every install, on every platform, ran it:
#
#     lib/hooks.sh: line 546: C:Usersname: command not found
#
# Non-fatal, which is how it survived: install output is normally redirected to a log
# and only the exit code is checked — exactly how it slipped past a local install run
# hours before it was reported. Found by the FIRST human Windows install.
#
# Note that shellcheck does NOT flag this at --severity=error, which is what CI
# enforces — so the linter was never going to catch it. (This line deliberately does
# not begin with the linter's name: a comment starting that way is parsed as a
# directive and fails with SC1073.)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SCAN="$(dirname "${BASH_SOURCE[0]}")/lib-interp-scan.py"

echo "=== Interpolated -c Block Safety ==="

begin_test "no command substitution inside a multi-line double-quoted -c block"
FOUND=$(python3 "$SCAN" "$REPO_DIR" 2>&1)
[ -z "$FOUND" ] && pass || fail "bash will execute these at runtime: $FOUND"

begin_test "the scan catches the defect when it is reintroduced"
# A scan that cannot fail is worse than no scan. The decoy is built with printf so
# the backtick never sits in this file's own syntax.
TMPD=$(mktemp -d); mkdir -p "$TMPD/lib" "$TMPD/hooks" "$TMPD/tools"
: > "$TMPD/install.sh"; : > "$TMPD/uninstall.sh"
BT=$(printf '\140')
{
  printf '%s\n' 'demo() {'
  printf '%s\n' '  python3 -c "'
  printf '%s\n' 'import os'
  printf '# example path is %sC:\\Users\\name%s here\n' "$BT" "$BT"
  printf '%s\n' 'print(os.sep)'
  printf '%s\n' '"'
  printf '%s\n' '}'
} > "$TMPD/lib/decoy.sh"
DETECT=$(python3 "$SCAN" "$TMPD" 2>&1)
rm -rf "$TMPD"
[ -n "$DETECT" ] && pass || fail "the scan did not catch a reintroduced backtick"

# One install, three assertions. Kept together because the run is slow, and split
# apart because "no error text" and "actually installed something" are different
# questions — checking only the first is what let a broken build read as fixed.
TH=$(mktemp -d); mkdir -p "$TH/home"
IOUT=$(HOME="$TH/home" bash "$REPO_DIR/install.sh" --mode full --roles developer \
         --config deploy --settings deploy --economy lean 2>&1)
IHOOKS=$(ls "$TH/home/.claude/supercharger/hooks/"*.sh 2>/dev/null | wc -l | tr -d ' ')
ISTATUS=$(jq -r '.statusLine.command // ""' "$TH/home/.claude/settings.json" 2>/dev/null)

begin_test "a real install emits no 'command not found'"
# BOTH streams: the error goes to stderr and is non-fatal, so an exit-code check
# alone misses it.
if printf '%s' "$IOUT" | grep -qiE 'command not found'; then
  fail "installer emitted: $(printf '%s' "$IOUT" | grep -i 'command not found' | head -2)"
else
  pass
fi

begin_test "the install actually placed hooks (silent-breakage check)"
# The failure mode a grep for error text CANNOT see. Closing the double-quoted -c
# string early — which a stray quote in that comment does — makes the python block
# emit nothing: install completes, prints no error, and installs ZERO hooks. That
# is precisely what happened while fixing the backtick, and only the full suite
# caught it.
[ "${IHOOKS:-0}" -gt 100 ] && pass || fail "expected >100 hooks installed, got ${IHOOKS:-0}"

begin_test "the install registered a statusline"
# Second casualty of the same breakage, and independent of the hook count.
[ -n "$ISTATUS" ] && pass || fail "statusLine absent from settings.json — the python block produced nothing"
rm -rf "$TH"

report
