#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/cmd-normalize.sh"

echo "=== Command Normalize Tests ==="

# shellcheck source=hooks/cmd-normalize.sh
. "$LIB"

# --- normalize_cmd ---

begin_test "normalize_cmd: trims leading whitespace"
OUT=$(normalize_cmd "   ls -la")
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: trims trailing whitespace"
OUT=$(normalize_cmd "ls -la   ")
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips leading backslash (PS1 escape)"
OUT=$(normalize_cmd '\ls -la')
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips single sudo prefix"
OUT=$(normalize_cmd "sudo rm -rf /tmp/x")
[ "$OUT" = "rm -rf /tmp/x" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips command prefix"
OUT=$(normalize_cmd "command ls")
[ "$OUT" = "ls" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips env prefix AND inline env-vars (v2.6.80)"
OUT=$(normalize_cmd "env FOO=bar ls")
[ "$OUT" = "ls" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips bare inline env-var prefix (v2.6.80)"
OUT=$(normalize_cmd "PATH=/usr/bin ls")
[ "$OUT" = "ls" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips multiple chained inline env-vars (v2.6.80)"
OUT=$(normalize_cmd "FOO=bar PATH=/usr/bin BAZ=qux ls -la")
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips nested sudo+command prefixes"
OUT=$(normalize_cmd "sudo command rm -rf /tmp/x")
[ "$OUT" = "rm -rf /tmp/x" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: collapses repeated spaces"
OUT=$(normalize_cmd "ls   -la    /tmp")
[ "$OUT" = "ls -la /tmp" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: leaves benign commands alone"
OUT=$(normalize_cmd "git status")
[ "$OUT" = "git status" ] && pass || fail "got: '$OUT'"

# --- split_segments ---

begin_test "split_segments: splits on &&"
OUT=$(split_segments "cd /tmp && ls -la")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && echo "$OUT" | grep -qx "cd /tmp" && echo "$OUT" | grep -qx "ls -la" && pass || fail "got: $OUT"

begin_test "split_segments: splits on ||"
OUT=$(split_segments "a || b")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs, got: $OUT"

begin_test "split_segments: splits on ;"
OUT=$(split_segments "a ; b ; c")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "3" ] && pass || fail "expected 3 segs, got: $OUT"

begin_test "split_segments: splits on | (pipe)"
OUT=$(split_segments "cat foo | grep bar")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs, got: $OUT"

begin_test "split_segments: does NOT split on && inside single quotes"
OUT=$(split_segments "echo 'a && b' ; ls")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs (quote-aware), got: $OUT"

begin_test "split_segments: does NOT split on ; inside double quotes"
OUT=$(split_segments "echo \"a ; b\" ; ls")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs (quote-aware), got: $OUT"

begin_test "split_segments: strips sudo from each segment"
OUT=$(split_segments "sudo rm -rf /tmp/a && sudo rm -rf /tmp/b")
echo "$OUT" | grep -qx "rm -rf /tmp/a" && echo "$OUT" | grep -qx "rm -rf /tmp/b" && pass || fail "got: $OUT"

begin_test "split_segments: single command returns 1 segment"
OUT=$(split_segments "ls -la")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "1" ] && pass || fail "got: $OUT"

begin_test "split_segments: empty input returns no segments"
OUT=$(split_segments "")
[ -z "$OUT" ] && pass || fail "got: $OUT"

# Regression (2.17.1): the split_segments python was passed via `python3 -c "..."`
# (double-quoted), and a comment held a literal-backtick example `...rm -rf /...`,
# so the SHELL command-substituted it and ran `rm -rf /` on EVERY compound command.
begin_test "split_segments: no shell command-substitution side effect (does not run rm)"
ERR=$(split_segments 'echo a; echo b' 2>&1 >/dev/null)
[ -z "$ERR" ] && pass || fail "split_segments produced stderr (cmd-subst side effect?): $ERR"

begin_test "cmd-normalize: no UNESCAPED backtick inside the python3 -c \"...\" block"
RAW=$(python3 -c "
import re, sys
s=open(sys.argv[1]).read()
bad=0
for b in re.findall(r'python3 -c \"(.*?)\"\s', s, re.S):
    bad += sum(1 for i,ch in enumerate(b) if ch=='\`' and (i==0 or b[i-1]!='\\\\'))
print(bad)
" "$REPO_DIR/hooks/cmd-normalize.sh" 2>/dev/null)
[ "$RAW" = "0" ] && pass || fail "unescaped backtick(s) in a -c block: $RAW (shell will command-substitute them)"

# --- v4.0.9: the space-collapse loop is size-gated -----------------------------
#
# `${cmd//  / }` rebuilds the whole string on every pass, and the passes multiply
# with the length. On a real 17.5KB command (a 276-line python heredoc, kept
# because python is an executor) that loop cost 147.94s against 0.03s for the
# `tr -s ' '` it claims to match — and four guards source this helper, so the
# command spent minutes in a PreToolUse hook and simply looked frozen.
#
# Both arms must produce the SAME answer, or the gate is a correctness bug rather
# than an optimisation. These pin the equivalence at sizes either side of the
# threshold, and the timing bound catches a reintroduced loop without being
# flaky: the fixed path is milliseconds, the broken one is minutes.

_collapse_ref() { printf '%s' "$1" | tr -s ' '; }

begin_test "normalize_cmd: collapses space runs identically below the fork gate"
SMALL="echo     a     b        c"
OUT=$(normalize_cmd "$SMALL")
[ "$OUT" = "echo a b c" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: both arms of the gate agree on the same input"
# Same string, forced down each path by moving the threshold, not by changing the
# input — otherwise the two runs would not be comparable.
PADDED="echo $(printf 'x     y     %.0s' 1 2 3 4 5 6 7 8 9 10)"
VIA_BASH=$(SUPERCHARGER_COLLAPSE_FORK_BYTES=999999 normalize_cmd "$PADDED")
VIA_TR=$(SUPERCHARGER_COLLAPSE_FORK_BYTES=1 normalize_cmd "$PADDED")
[ "$VIA_BASH" = "$VIA_TR" ] && pass \
  || fail "gate arms disagree: bash='$VIA_BASH' tr='$VIA_TR'"

begin_test "normalize_cmd: tabs survive the collapse (spaces only, not tabs)"
# tr -s ' ' squeezes spaces alone; the pure-bash loop did too. A tab-squeezing
# replacement would silently change what every guard matches against.
OUT=$(normalize_cmd "echo$(printf '\t\t')a  b")
case "$OUT" in
  *"$(printf '\t\t')"*) pass ;;
  *) fail "tabs were collapsed: $(printf '%s' "$OUT" | od -c | head -2)" ;;
esac

begin_test "normalize_cmd: a large space-heavy command finishes promptly"
# 8KB of two-space runs. Pre-fix this took minutes; the bound is deliberately
# loose (15s) so it fails on a reintroduced quadratic loop, never on a slow box.
BIG="echo $(awk 'BEGIN{for(i=0;i<800;i++) printf "aa  bb  cc  dd  "}')"
_T0=$(date +%s)
OUT=$(normalize_cmd "$BIG")
_T1=$(date +%s)
_ELAPSED=$(( _T1 - _T0 ))
REF="echo $(_collapse_ref "$(awk 'BEGIN{for(i=0;i<800;i++) printf "aa  bb  cc  dd  "}')")"
REF="${REF%"${REF##*[![:space:]]}"}"
if [ "$_ELAPSED" -ge 15 ]; then
  fail "took ${_ELAPSED}s — the collapse loop is quadratic again"
elif [ "$OUT" != "$REF" ]; then
  fail "output differs from tr -s ' ' at ${#BIG} bytes"
else
  pass
fi

report
